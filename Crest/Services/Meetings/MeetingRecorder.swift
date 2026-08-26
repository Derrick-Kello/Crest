//
//  MeetingRecorder.swift
//  Crest
//

import AVFoundation
import AppKit
import Foundation
import Observation
import OSLog

/// Records a meeting from both sides at once and summarizes it on-device.
///
/// The design decision worth knowing: **two captures, two transcribers, one timeline.**
/// The microphone is you and the system output is everyone else, so running a separate
/// speech session on each gives correct speaker attribution for free. The alternative —
/// one mixed recording plus a diarization model — needs another model download, another
/// second of latency, and still only guesses at who is who.
///
/// Nothing leaves the Mac. Both transcribers are Apple's on-device `SpeechAnalyzer`, and
/// the summary is Apple's on-device language model.
@MainActor
@Observable
final class MeetingRecorder {
    nonisolated enum State: Equatable {
        case idle
        case starting
        case recording
        case stopping
        /// Summarizing, with 0…1 progress. The map pass over a long meeting takes a
        /// while, and a bar that moves is the difference between waiting and worrying.
        case summarizing(Double)
        case error(String)

        var isRecording: Bool { self == .recording || self == .starting }

        var isSummarizing: Bool {
            if case .summarizing = self { return true }
            return false
        }
    }

    /// Called on every state change, for the same reason as the dictation HUD: ordering
    /// an AppKit panel in and out is a side effect, not a view update.
    var onStateChange: (() -> Void)?

    private(set) var state: State = .idle {
        didSet {
            guard state != oldValue else { return }
            onStateChange?()
        }
    }

    /// The app Crest noticed a call in, while the offer to take notes is standing.
    private(set) var suggestion: String? {
        didSet {
            guard suggestion != oldValue else { return }
            onStateChange?()
        }
    }
    /// The meeting being recorded, updated live so the transcript can be read as it
    /// happens rather than only afterwards.
    private(set) var current: Meeting?
    private(set) var micLevel: Float = 0
    private(set) var systemLevel: Float = 0
    private(set) var elapsed: TimeInterval = 0
    /// Set when the system-audio half could not start but the microphone did. The
    /// meeting still records; it only hears your side, and saying so beats a transcript
    /// that mysteriously contains half a conversation.
    private(set) var systemAudioWarning: String?

    let detector = CallDetector()

    private let microphone = MicrophoneTap()
    private let systemAudio = SystemAudioTap()

    private var engines: [AudioSource: any SpeechEngine] = [:]
    private var feedTasks: [AudioSource: Task<Void, Never>] = [:]
    private var consumeTasks: [AudioSource: Task<Void, Never>] = [:]
    private var continuations: [AudioSource: AsyncStream<AudioChunk>.Continuation] = [:]
    private var committed: [AudioSource: String] = [:]
    private var lastSegmentAt: [AudioSource: Date] = [:]
    private var tickTask: Task<Void, Never>?
    private var summarizeTask: Task<Void, Never>?

    /// A pause longer than this starts a new paragraph rather than extending the last
    /// one. Twelve seconds is long enough that continuing the same line would be wrong
    /// and short enough that a normal exchange stays together.
    private static let segmentGap: TimeInterval = 12

    // MARK: - Lifecycle

    func startDetecting() {
        guard Preferences.meetingsEnabled, Preferences.meetingSuggestOnCall else {
            detector.stop()
            suggestion = nil
            return
        }
        detector.onCallDetected = { [weak self] application in
            guard let self, case .idle = self.state else { return }
            self.suggestion = application
        }
        detector.start()
    }

    func stopDetecting() {
        detector.stop()
        suggestion = nil
    }

    /// Starts recording the call that prompted the offer.
    func acceptSuggestion() {
        let application = suggestion
        suggestion = nil
        guard application != nil else { return }
        start()
    }

    /// Turns down the offer for this call only. It comes back for the next one, which is
    /// the difference between a prompt and a nag.
    func dismissSuggestion() {
        suggestion = nil
        detector.dismissCurrent()
    }

    // MARK: - Recording

    func start(title: String? = nil) {
        guard case .idle = state else { return }
        suggestion = nil
        state = .starting
        systemAudioWarning = nil
        committed = [:]
        lastSegmentAt = [:]
        elapsed = 0

        let application = CallDetector.runningCallApplication()
        let meeting = Meeting(
            title: title ?? Self.defaultTitle(application: application),
            applicationName: application
        )
        current = meeting

        Task { @MainActor in
            do {
                if Preferences.meetingCaptureMicrophone {
                    guard await VoicePermissions.requestMicrophone() else {
                        throw SpeechEngineError.microphoneDenied
                    }
                    try await startSide(.microphone)
                }
                if Preferences.meetingCaptureSystemAudio {
                    do {
                        try await startSide(.system)
                    } catch {
                        // A missing screen-recording grant should not throw away the half
                        // of the meeting that does work. Record your side and say why the
                        // other side is missing.
                        systemAudioWarning = error.localizedDescription
                        VoiceLog.meeting.error("system audio unavailable: \(error.localizedDescription, privacy: .public)")
                    }
                }
                guard !engines.isEmpty else {
                    throw SpeechEngineError.microphoneDenied
                }

                state = .recording
                startTicking()
            } catch {
                await teardownCaptures()
                current = nil
                state = .error(error.localizedDescription)
                clearErrorLater()
            }
        }
    }

    private func startSide(_ source: AudioSource) async throws {
        let engine = AppleSpeechEngine(biasPhrases: VocabularyStore.shared.biasPhrases)
        let chunks = try await engine.start()
        guard let format = await engine.preferredInputFormat() else {
            throw SpeechEngineError.noAudioFormat
        }

        // One stream drained by one task, so buffers reach the engine in capture order.
        // A task per buffer would be simpler and would silently scramble the transcript.
        let (stream, continuation) = AsyncStream<AudioChunk>.makeStream(
            bufferingPolicy: .bufferingNewest(256)
        )
        continuations[source] = continuation
        engines[source] = engine

        feedTasks[source] = Task.detached(priority: .userInitiated) {
            for await chunk in stream { await engine.feed(chunk) }
        }

        consumeTasks[source] = Task { @MainActor [weak self] in
            do {
                for try await chunk in chunks {
                    self?.absorb(chunk, from: source)
                }
            } catch {
                VoiceLog.meeting.error("\(source.rawValue, privacy: .public) transcription failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        switch source {
        case .microphone:
            try microphone.start(
                outputFormat: format,
                onBuffer: { continuation.yield($0) },
                onLevel: { [weak self] level in
                    Task { @MainActor [weak self] in self?.updateLevel(level, for: .microphone) }
                }
            )
        case .system:
            try await systemAudio.start(
                outputFormat: format,
                onBuffer: { continuation.yield($0) },
                onLevel: { [weak self] level in
                    Task { @MainActor [weak self] in self?.updateLevel(level, for: .system) }
                },
                onStop: { [weak self] error in
                    Task { @MainActor [weak self] in
                        self?.systemAudioWarning = error.localizedDescription
                    }
                }
            )
        }
    }

    func stop() {
        guard state.isRecording else { return }
        state = .stopping
        tickTask?.cancel()
        tickTask = nil
        micLevel = 0
        systemLevel = 0

        Task { @MainActor in
            await teardownCaptures()

            guard var meeting = current else {
                state = .idle
                return
            }
            meeting.endedAt = Date()
            current = meeting

            guard !meeting.isEmpty else {
                // An empty recording is a mis-click, not a meeting. Saving it would leave
                // a row nobody can do anything with.
                current = nil
                state = .idle
                return
            }

            MeetingStore.shared.save(meeting)
            state = .idle

            if Preferences.meetingAutoSummarize, ModelCleanup.isAvailable {
                summarize(id: meeting.id)
            } else {
                current = nil
            }
        }
    }

    /// Drops the recording without saving anything.
    func discard() {
        guard state.isRecording else { return }
        tickTask?.cancel()
        tickTask = nil
        Task { @MainActor in
            await teardownCaptures()
            current = nil
            micLevel = 0
            systemLevel = 0
            state = .idle
        }
    }

    // MARK: - Summarizing

    /// Runs the summarizer over a saved meeting. Safe to call again to regenerate.
    func summarize(id: UUID) {
        guard summarizeTask == nil else { return }
        guard var meeting = MeetingStore.shared.meeting(id: id) else { return }

        state = .summarizing(0)
        summarizeTask = Task { @MainActor in
            defer {
                summarizeTask = nil
                current = nil
            }
            do {
                let summary = try await MeetingSummarizer().summarize(meeting.plainTranscript) { fraction in
                    Task { @MainActor [weak self] in self?.state = .summarizing(fraction) }
                }
                meeting.summary = summary
                MeetingStore.shared.save(meeting)
                state = .idle
            } catch {
                state = .error(error.localizedDescription)
                clearErrorLater()
            }
        }
    }

    // MARK: - Transcript assembly

    /// Folds one engine snapshot into the timeline.
    ///
    /// Only the *committed* half of a snapshot is used. The volatile half is rewritten by
    /// the engine as it hears more, so appending it would put half-heard words into the
    /// transcript permanently and then leave them there when the engine changed its mind.
    private func absorb(_ chunk: TranscriptionChunk, from source: AudioSource) {
        let previous = committed[source] ?? ""
        let text = chunk.committedText
        guard text.count > previous.count, text.hasPrefix(previous) else {
            committed[source] = text
            return
        }

        let delta = String(text.dropFirst(previous.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        committed[source] = text
        guard !delta.isEmpty, var meeting = current else { return }

        let now = Date()
        let gap = now.timeIntervalSince(lastSegmentAt[source] ?? .distantPast)
        let canExtend = gap < Self.segmentGap
            && meeting.segments.last?.source == source

        if canExtend, var last = meeting.segments.last {
            last.text += " " + delta
            meeting.segments[meeting.segments.count - 1] = last
        } else {
            meeting.segments.append(
                TranscriptSegment(
                    source: source,
                    offset: now.timeIntervalSince(meeting.startedAt),
                    text: delta
                )
            )
        }

        lastSegmentAt[source] = now
        current = meeting
    }

    // MARK: - Plumbing

    private func teardownCaptures() async {
        microphone.stop()
        await systemAudio.stop()

        for (_, continuation) in continuations { continuation.finish() }
        continuations = [:]

        for (_, task) in feedTasks { await task.value }
        feedTasks = [:]

        for (_, engine) in engines { await engine.finish() }
        engines = [:]

        for (_, task) in consumeTasks { await task.value }
        consumeTasks = [:]
    }

    /// Light smoothing, so a meter glides instead of strobing at buffer rate.
    private func updateLevel(_ new: Float, for source: AudioSource) {
        switch source {
        case .microphone: micLevel += (new - micLevel) * 0.35
        case .system: systemLevel += (new - systemLevel) * 0.35
        }
    }

    private func startTicking() {
        tickTask?.cancel()
        tickTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, let meeting = self.current else { return }
                self.elapsed = Date().timeIntervalSince(meeting.startedAt)
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func clearErrorLater() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))
            if case .error = state { state = .idle }
        }
    }

    private static func defaultTitle(application: String?) -> String {
        let time = Date().formatted(date: .omitted, time: .shortened)
        guard let application else { return "Meeting at \(time)" }
        return "\(application) call at \(time)"
    }
}
