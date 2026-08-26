//
//  DictationService.swift
//  Crest
//

import AVFoundation
import AppKit
import Foundation
import OSLog
import Observation

/// How much work goes into tidying a transcript before it is typed.
nonisolated enum CleanupMode: String, CaseIterable, Codable, Sendable, Identifiable {
    /// Type exactly what the engine heard.
    case off
    /// Deterministic pass: fillers out, punctuation and capitals in. Zero added latency.
    case rules
    /// The on-device model, with the rule pass as its fallback.
    case model

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: "Raw"
        case .rules: "Tidy"
        case .model: "Smart"
        }
    }

    var blurb: String {
        switch self {
        case .off: "Type exactly what was heard"
        case .rules: "Strip fillers, fix punctuation and capitals. Instant."
        case .model: "On-device model: honours spoken corrections and formats lists. Adds about a second."
        }
    }
}

/// Push-to-talk dictation: hold a key, talk, release, and cleaned-up text lands in
/// whatever had focus.
///
/// The state machine and its edges are the whole of this type. Everything it drives —
/// capture, transcription, cleanup, injection — lives behind a protocol or a static
/// helper so that none of them know about each other.
@MainActor
@Observable
final class DictationService {
    nonisolated enum Phase: Equatable {
        case idle
        case starting
        case listening
        case finishing
        /// Command mode, waiting on the model to rewrite the selection.
        case rewriting
        case error(String)
        /// Something worth saying that is not a failure: text copied instead of typed,
        /// a password field skipped. Clears itself.
        case notice(String)

        var isRecording: Bool {
            switch self {
            case .starting, .listening: true
            default: false
            }
        }

        var isBusy: Bool {
            switch self {
            case .starting, .listening, .finishing, .rewriting: true
            case .idle, .error, .notice: false
            }
        }
    }

    /// Called on every phase change. The HUD is an AppKit panel that has to be ordered
    /// in and out, which is a side effect rather than a view update — so it is driven by
    /// a callback rather than by observation.
    var onPhaseChange: (() -> Void)?

    private(set) var phase: Phase = .idle {
        didSet {
            guard phase != oldValue else { return }
            onPhaseChange?()
        }
    }
    /// Live transcript, revised as the engine changes its mind. Drives the HUD.
    private(set) var transcript = ""
    /// Smoothed 0…1 microphone level for the waveform.
    private(set) var level: Float = 0
    /// True when a quick tap locked the microphone open, so the HUD can say so and the
    /// next tap knows to stop rather than start.
    private(set) var isHandsFree = false
    /// What the current utterance is for.
    private(set) var role: PushToTalkRole = .dictate
    /// Set when the event tap could not be installed. The one thing the user has to fix
    /// themselves, so it is surfaced rather than logged.
    private(set) var needsAccessibility = false
    /// The microphone grant, mirrored here so the UI can react to it.
    ///
    /// `AVCaptureDevice.authorizationStatus` is a plain function call, not something
    /// observation can watch, so a view reading it directly would keep showing the state
    /// it saw when it was first built — including right after the user granted access.
    private(set) var microphoneAccess = AVCaptureDevice.authorizationStatus(for: .audio)
    /// The style the current recording will be cleaned with, decided at press time.
    private(set) var activeStyle: DictationStyle = .prose
    private(set) var targetAppName: String?

    private let monitor = PushToTalkMonitor()
    private let microphone = MicrophoneTap()
    private let history = DictationHistory.shared

    private var engine: (any SpeechEngine)?
    private var consumeTask: Task<Void, Never>?
    private var feedTask: Task<Void, Never>?
    private var audioContinuation: AsyncStream<AudioChunk>.Continuation?
    private var noticeTask: Task<Void, Never>?
    private var accessibilityPoll: Task<Void, Never>?

    private var pressedAt: Date?
    private var releasedAt: Date?
    private var targetBundleIdentifier: String?
    /// Command mode only: what was selected when the key went down.
    private var capturedSelection: String?

    /// A press-and-release shorter than this is a tap, not a hold. 350 ms is above a
    /// deliberate tap and well below the shortest useful utterance, so the two do not
    /// overlap in practice.
    private static let tapThreshold: TimeInterval = 0.35

    var isEnabled: Bool { Preferences.voiceEnabled }

    // MARK: - Lifecycle

    /// Arms or disarms the key watcher to match the current settings.
    ///
    /// Called at launch and after every settings change. Cheap and idempotent, so the
    /// whole thing is rebuilt rather than diffed.
    func reload() {
        guard Preferences.voiceEnabled else {
            monitor.stop()
            accessibilityPoll?.cancel()
            accessibilityPoll = nil
            needsAccessibility = false
            cancel()
            return
        }

        monitor.dictateKey = Preferences.pushToTalkKey
        monitor.commandKey = Preferences.commandModeEnabled ? Preferences.commandModeKey : nil
        monitor.onPress = { [weak self] role in self?.keyPressed(role) }
        monitor.onRelease = { [weak self] role in self?.keyReleased(role) }
        monitor.onCancel = { [weak self] in self?.cancel() }

        needsAccessibility = !monitor.start()
        needsAccessibility ? startAccessibilityPoll() : stopAccessibilityPoll()
    }

    /// Re-reads both grants. Views call this when they appear, because TCC changes
    /// happen in System Settings, outside anything this process can observe.
    func refreshPermissions() {
        microphoneAccess = AVCaptureDevice.authorizationStatus(for: .audio)
        if Preferences.voiceEnabled, needsAccessibility, AXIsProcessTrusted() {
            needsAccessibility = !monitor.start()
        }
    }

    /// Asks for the microphone, or sends the user to System Settings when asking is no
    /// longer possible.
    ///
    /// The distinction matters and is easy to get wrong: an app that has never asked
    /// does not appear in the Microphone list in System Settings at all, so opening that
    /// pane for a `.notDetermined` app shows a list the user cannot find Crest in.
    /// Only a denial puts it there, and only then is opening the pane the useful move.
    func requestMicrophoneAccess() async {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            VoicePermissions.openMicrophoneSettings()
        default:
            break
        }
        refreshPermissions()
    }

    /// Asks for everything dictation needs, at the moment the user switches it on.
    ///
    /// Deliberately not deferred to the first utterance. The microphone prompt takes
    /// focus, and arriving mid-hold it would both interrupt the recording and land on
    /// top of the app the text was meant for. Turning the feature on is when the user is
    /// looking at the screen and expecting to be asked.
    func requestPermissions() async {
        await requestMicrophoneAccess()
        if !AXIsProcessTrusted() {
            VoicePermissions.promptForAccessibility()
        }
        refreshPermissions()
    }

    /// Polls for the Accessibility grant so the tap arms the moment it is given, without
    /// the user having to quit and relaunch.
    ///
    /// Two seconds, and only while the grant is actually missing: `AXIsProcessTrusted` is
    /// a cheap call, but a permanent timer for a condition that is normally false is
    /// exactly the kind of idle cost Crest exists to avoid.
    private func startAccessibilityPoll() {
        guard accessibilityPoll == nil else { return }
        accessibilityPoll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self, Preferences.voiceEnabled, self.needsAccessibility else { return }
                guard AXIsProcessTrusted() else { continue }
                self.needsAccessibility = !self.monitor.start()
                if !self.needsAccessibility { return }
            }
        }
    }

    private func stopAccessibilityPoll() {
        accessibilityPoll?.cancel()
        accessibilityPoll = nil
    }

    /// Starts a recording from a button rather than the key, for anyone who would rather
    /// not hold anything down. Always hands-free, since there is no key to release.
    func toggleFromButton() {
        if phase.isRecording {
            isHandsFree = false
            finish()
            return
        }
        guard case .idle = phase else { return }
        isHandsFree = true
        begin(role: .dictate)
    }

    // MARK: - Key edges

    private func keyPressed(_ role: PushToTalkRole) {
        // A press while the microphone is locked open means "stop", not "start again".
        if isHandsFree, phase.isRecording {
            isHandsFree = false
            finish()
            return
        }
        guard case .idle = phase else { return }
        pressedAt = Date()
        begin(role: role)
    }

    private func keyReleased(_ role: PushToTalkRole) {
        guard phase.isRecording, role == self.role else { return }

        // A quick tap locks the microphone open instead of stopping a recording that had
        // no time to hear anything. This is the difference between push-to-talk and
        // hands-free being two features and being one key that does the obvious thing.
        let held = pressedAt.map { Date().timeIntervalSince($0) } ?? .infinity
        if Preferences.voiceHandsFreeEnabled, role == .dictate, held < Self.tapThreshold {
            isHandsFree = true
            return
        }

        finish()
    }

    // MARK: - Recording

    private func begin(role: PushToTalkRole) {
        self.role = role
        phase = .starting
        transcript = ""
        pressedAt = pressedAt ?? Date()
        releasedAt = nil

        // Read the target *now*. By the time an utterance finishes the user may have
        // switched apps, and the style has to match where the text is going to land.
        targetBundleIdentifier = TextInjector.frontmostBundleIdentifier()
        targetAppName = TextInjector.frontmostApplicationName()
        activeStyle = resolvedStyle(for: targetBundleIdentifier)

        if role == .command {
            capturedSelection = TextInjector.selectedText()
            guard capturedSelection != nil else {
                fail("Select some text first, then hold the key and say what to do with it.")
                return
            }
        } else {
            capturedSelection = nil
        }

        monitor.startWatchingForCancel()

        Task { @MainActor in
            do {
                guard await Self.requestMicrophone() else {
                    fail(SpeechEngineError.microphoneDenied.localizedDescription)
                    return
                }

                let engine = AppleSpeechEngine(biasPhrases: VocabularyStore.shared.biasPhrases)
                self.engine = engine

                let chunks = try await engine.start()
                guard let format = await engine.preferredInputFormat() else {
                    throw SpeechEngineError.noAudioFormat
                }

                // Audio must reach the engine in capture order. A stream drained by a
                // single task guarantees that; spawning a task per buffer would not —
                // unstructured tasks have no ordering guarantee, and out-of-order
                // buffers produce word salad rather than an obvious failure.
                let (audioStream, audioContinuation) = AsyncStream<AudioChunk>.makeStream(
                    bufferingPolicy: .bufferingNewest(64)
                )
                self.audioContinuation = audioContinuation

                self.feedTask = Task.detached(priority: .userInitiated) {
                    for await chunk in audioStream {
                        await engine.feed(chunk)
                    }
                }

                try microphone.start(
                    outputFormat: format,
                    onBuffer: { audioContinuation.yield($0) },
                    onLevel: { [weak self] level in
                        Task { @MainActor [weak self] in self?.updateLevel(level) }
                    }
                )

                // Bail out if the user already let go while this was spinning up.
                guard case .starting = self.phase else {
                    await self.teardown()
                    return
                }

                self.phase = .listening
                self.playSound("Tink")

                self.consumeTask = Task { @MainActor in
                    do {
                        for try await chunk in chunks {
                            self.transcript = chunk.text
                        }
                    } catch {
                        self.fail(error.localizedDescription)
                    }
                }
            } catch {
                self.fail(error.localizedDescription)
            }
        }
    }

    private func finish() {
        // `.finishing` is busy but not recording, so without this guard a second press
        // during processing would run the whole tail again — re-reading `transcript`
        // before the first pass cleared it and typing the same utterance twice. The
        // window is wide: smart cleanup alone can add a second.
        guard phase.isRecording else { return }
        phase = .finishing
        microphone.stop()
        monitor.stopWatchingForCancel()
        level = 0
        releasedAt = Date()

        Task { @MainActor in
            // Every captured buffer has to reach the engine before it is asked to
            // finalize, or the tail of the utterance is dropped.
            audioContinuation?.finish()
            audioContinuation = nil
            await feedTask?.value
            feedTask = nil

            await engine?.finish()
            await consumeTask?.value
            consumeTask = nil
            engine = nil

            let raw = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else {
                phase = .idle
                transcript = ""
                return
            }

            switch role {
            case .dictate: await completeDictation(raw: raw)
            case .command: await completeCommand(instruction: raw)
            }
        }
    }

    private func completeDictation(raw: String) async {
        let style = activeStyle
        let cleaned: String = switch Preferences.dictationCleanup {
        case .off: raw
        case .rules: await RuleBasedCleanup().clean(raw, style: style)
        case .model: await ModelCleanup().clean(raw, style: style)
        }

        // The vocabulary runs last, and runs regardless of the cleanup setting. Biasing
        // only raises the odds of the right word; this is the pass that guarantees it,
        // so it must not be something the user can switch off by accident.
        let (output, corrections) = VocabularyStore.shared.corrector.apply(to: cleaned)

        let outcome = TextInjector.insert(output)
        if outcome == .refusedSecureField {
            phase = .idle
            transcript = ""
            showNotice("That's a password field — nothing was typed.")
            return
        }

        record(text: output, corrections: corrections)
        playSound("Pop")

        phase = .idle
        transcript = ""
    }

    private func completeCommand(instruction: String) async {
        guard let selection = capturedSelection else {
            phase = .idle
            transcript = ""
            return
        }
        capturedSelection = nil

        phase = .rewriting
        transcript = instruction

        do {
            let rewritten = try await SelectionRewriter().rewrite(selection, instruction: instruction)
            // Replaces the selection, which is still selected: the HUD never took focus,
            // so the user's app has not moved on.
            let outcome = TextInjector.insert(rewritten)
            if outcome == .refusedSecureField {
                phase = .idle
                transcript = ""
                showNotice("That's a password field — nothing was changed.")
                return
            }
            playSound("Pop")
            phase = .idle
            transcript = ""
        } catch {
            fail(error.localizedDescription)
        }
    }

    /// Drops everything without typing anything. Escape, or the service being turned off
    /// mid-utterance.
    func cancel() {
        guard phase.isBusy else { return }
        microphone.stop()
        monitor.stopWatchingForCancel()
        audioContinuation?.finish()
        audioContinuation = nil
        feedTask?.cancel()
        feedTask = nil
        consumeTask?.cancel()
        consumeTask = nil

        let engine = self.engine
        self.engine = nil
        Task { await engine?.finish() }

        isHandsFree = false
        capturedSelection = nil
        phase = .idle
        transcript = ""
        level = 0
    }

    private func teardown() async {
        microphone.stop()
        monitor.stopWatchingForCancel()
        audioContinuation?.finish()
        audioContinuation = nil
        await feedTask?.value
        feedTask = nil
        await engine?.finish()
        engine = nil
        consumeTask?.cancel()
        consumeTask = nil
        isHandsFree = false
        phase = .idle
    }

    // MARK: - Style

    /// Explicit per-app choice, then the global choice, then the built-in table.
    private func resolvedStyle(for bundleIdentifier: String?) -> DictationStyle {
        if let bundleIdentifier, let override = Preferences.dictationStyleOverrides[bundleIdentifier] {
            return override
        }
        if let fixed = Preferences.dictationStyle { return fixed }
        return DictationStyle.forApplication(bundleIdentifier: bundleIdentifier)
    }

    /// Pins a style to an app, so "Slack always gets chat style" is one click from the
    /// history row rather than a settings expedition.
    func setStyle(_ style: DictationStyle?, forBundleIdentifier identifier: String) {
        var overrides = Preferences.dictationStyleOverrides
        if let style {
            overrides[identifier] = style
        } else {
            overrides.removeValue(forKey: identifier)
        }
        Preferences.dictationStyleOverrides = overrides
    }

    // MARK: - Helpers

    private func record(text: String, corrections: [AppliedCorrection]) {
        guard let pressedAt, let releasedAt else { return }
        history.record(
            Dictation(
                date: releasedAt,
                text: text,
                appName: targetAppName,
                bundleIdentifier: targetBundleIdentifier,
                style: activeStyle,
                audioSeconds: releasedAt.timeIntervalSince(pressedAt),
                processSeconds: Date().timeIntervalSince(releasedAt),
                corrections: corrections.isEmpty ? nil : corrections
            )
        )
        self.pressedAt = nil
        self.releasedAt = nil
        isHandsFree = false
    }

    /// Light smoothing so the waveform glides instead of strobing at buffer rate.
    private func updateLevel(_ new: Float) {
        level += (new - level) * 0.35
    }

    private func playSound(_ name: String) {
        guard Preferences.voiceSoundEnabled else { return }
        NSSound(named: name)?.play()
    }

    private func showNotice(_ message: String) {
        phase = .notice(message)
        noticeTask?.cancel()
        noticeTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            if case .notice = phase { phase = .idle }
        }
    }

    private func fail(_ message: String) {
        VoiceLog.speech.error("\(message, privacy: .public)")
        microphone.stop()
        monitor.stopWatchingForCancel()
        audioContinuation?.finish()
        audioContinuation = nil
        feedTask?.cancel()
        feedTask = nil
        consumeTask?.cancel()
        consumeTask = nil
        engine = nil
        capturedSelection = nil
        isHandsFree = false
        phase = .error(message)
        level = 0

        noticeTask?.cancel()
        noticeTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            if case .error = phase { phase = .idle }
        }
    }

    private static func requestMicrophone() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: .audio)
        default: false
        }
    }
}

/// The two grants the voice features need, and neither can be worked around.
///
/// Accessibility has no programmatic request — the OS only shows a prompt, and the user
/// has to flip the switch themselves. TCC also keys on the code signature, so re-signing
/// the app resets the grant.
@MainActor
enum VoicePermissions {
    static var hasAccessibility: Bool { AXIsProcessTrusted() }

    static var hasMicrophone: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    /// Shows the system Accessibility prompt if the app is not trusted yet.
    @discardableResult
    static func promptForAccessibility() -> Bool {
        // Spelled out rather than using `kAXTrustedCheckOptionPrompt`, which imports as a
        // mutable global and so is not usable from concurrency-checked code.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func requestMicrophone() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: .audio)
        default: false
        }
    }

    static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    static func openMicrophoneSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
    }

    /// Clears Crest's own Accessibility grant so the system will ask again.
    ///
    /// This exists because of a failure that is otherwise unfixable from inside the app
    /// and unguessable from outside it. TCC stores a code-signing requirement per grant,
    /// and an ad-hoc signature changes on every build — so a rebuilt Crest no longer
    /// satisfies the requirement stored against the old one. The symptom is the nasty
    /// part: System Settings still shows the toggle **on** while the app is reported
    /// untrusted, and switching it off and on again changes nothing, because the stale
    /// row is the problem rather than its value.
    ///
    /// Resetting drops the rows and lets the app ask cleanly. Scoped to this bundle
    /// identifier: a bare `tccutil reset Accessibility` wipes the grant for every app on
    /// the Mac.
    @discardableResult
    static func resetAccessibilityGrant() -> Bool {
        do {
            _ = try ProcessRunner.run(
                "/usr/bin/tccutil",
                arguments: ["reset", "Accessibility", Bundle.main.bundleIdentifier ?? "com.silvergrade.Crest"]
            )
            return true
        } catch {
            VoiceLog.audio.error("tccutil reset failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    static func openScreenRecordingSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    private static func open(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }
}
