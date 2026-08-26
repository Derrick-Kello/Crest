//
//  PushToTalkMonitor.swift
//  Crest
//

import AppKit
import Carbon.HIToolbox
import Foundation
import OSLog

/// Which modifier key holds the microphone open.
///
/// A bare modifier rather than a `HotKeyCombo`, and therefore a different mechanism from
/// the rest of Crest's shortcuts: Carbon's `RegisterEventHotKey` cannot register a
/// modifier on its own, and it reports presses, never releases. Push-to-talk needs both
/// edges of one key, which only an event tap gives you.
nonisolated enum PushToTalkKey: String, CaseIterable, Codable, Sendable, Identifiable {
    case rightOption
    case rightCommand
    case rightControl
    case leftOption
    case fn

    var id: String { rawValue }

    var keyCode: Int64 {
        switch self {
        case .rightOption: Int64(kVK_RightOption)     // 61
        case .rightCommand: Int64(kVK_RightCommand)   // 54
        case .rightControl: Int64(kVK_RightControl)   // 62
        case .leftOption: Int64(kVK_Option)           // 58
        case .fn: Int64(kVK_Function)                 // 63
        }
    }

    /// The device-*dependent* bit for this specific physical key.
    ///
    /// `CGEventFlags.maskAlternate` is the union mask — set whenever *either* Option key
    /// is down. Using it means: hold Left ⌥, tap Right ⌥, and the release is invisible,
    /// because the union bit is still set by the left key. `onRelease` never fires, the
    /// microphone stays open, the HUD stays up, and the next press is swallowed too.
    ///
    /// These raw values are IOKit's `NX_DEVICE*` masks, which carry the left/right
    /// distinction that the public `CGEventFlags` constants discard.
    var flag: CGEventFlags {
        switch self {
        case .rightOption: CGEventFlags(rawValue: 0x40)   // NX_DEVICERALTKEYMASK
        case .rightCommand: CGEventFlags(rawValue: 0x10)  // NX_DEVICERCMDKEYMASK
        case .rightControl: CGEventFlags(rawValue: 0x2000) // NX_DEVICERCTLKEYMASK
        case .leftOption: CGEventFlags(rawValue: 0x20)    // NX_DEVICELALTKEYMASK
        case .fn: .maskSecondaryFn                        // no left/right variant exists
        }
    }

    var displayName: String {
        switch self {
        case .rightOption: "Right ⌥"
        case .rightCommand: "Right ⌘"
        case .rightControl: "Right ⌃"
        case .leftOption: "Left ⌥"
        case .fn: "fn"
        }
    }

    /// Swallowing `fn` would break fn+arrow, fn+delete and the emoji picker, so it is
    /// passed through. Dedicated right-hand modifiers are safe to consume.
    var shouldConsumeEvent: Bool { self != .fn }
}

/// What a monitored key is for.
nonisolated enum PushToTalkRole: Sendable {
    /// Hold to dictate.
    case dictate
    /// Hold to rewrite whatever is selected, by voice.
    case command
}

/// Watches for held modifier keys using a `CGEventTap`.
///
/// A tap is required rather than `NSEvent.addGlobalMonitor` because `fn` and left/right
/// modifier discrimination do not surface through the higher-level APIs. This needs
/// Accessibility permission; without it `CGEvent.tapCreate` returns nil.
///
/// One tap watches both keys. Two taps would work and would double the per-keystroke
/// cost on a hot path that sees every modifier change on the system.
@MainActor
final class PushToTalkMonitor {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var pressed: Set<Int64> = []
    private var escapeMonitor: Any?

    /// The dictation key. Always watched while the monitor is running.
    var dictateKey: PushToTalkKey = .rightOption
    /// The command-mode key, or nil when command mode is off.
    var commandKey: PushToTalkKey?

    var onPress: ((PushToTalkRole) -> Void)?
    var onRelease: ((PushToTalkRole) -> Void)?
    /// Escape, while something is being recorded. Wired separately because it is an
    /// ordinary key, not a modifier, and it only matters mid-recording.
    var onCancel: (() -> Void)?

    /// - Returns: false when the tap could not be created — almost always Accessibility
    ///   permission that has not been granted yet.
    @discardableResult
    func start() -> Bool {
        stop()

        let mask = (1 << CGEventType.flagsChanged.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<PushToTalkMonitor>.fromOpaque(refcon).takeUnretainedValue()

                // `CGEvent` is not Sendable, so the plain values are pulled out before
                // crossing into actor-isolated code. The tap is on the main run loop, so
                // this callback genuinely does run on the main thread.
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let flags = event.flags
                let consume = MainActor.assumeIsolated {
                    monitor.handle(type: type, keyCode: keyCode, flags: flags)
                }
                return consume ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        ) else {
            VoiceLog.audio.error("push-to-talk tapCreate failed — Accessibility permission missing?")
            return false
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        VoiceLog.audio.info("push-to-talk listening for \(self.dictateKey.displayName, privacy: .public)")
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        pressed.removeAll()
        stopWatchingForCancel()
    }

    /// Escape is only interesting while a recording is running, so the monitor for it
    /// exists only for that long rather than sitting on every keystroke all day.
    func startWatchingForCancel() {
        guard escapeMonitor == nil else { return }
        escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == UInt16(kVK_Escape) else { return }
            MainActor.assumeIsolated { self?.onCancel?() }
        }
    }

    func stopWatchingForCancel() {
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
    }

    // MARK: - Tap callback

    /// - Returns: true if the event should be swallowed rather than passed along.
    private func handle(type: CGEventType, keyCode: Int64, flags: CGEventFlags) -> Bool {
        // The system disables a tap that runs too slowly or is interrupted; re-arm it.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }

        guard type == .flagsChanged else { return false }

        let role: PushToTalkRole
        let key: PushToTalkKey
        if keyCode == dictateKey.keyCode {
            role = .dictate
            key = dictateKey
        } else if let commandKey, keyCode == commandKey.keyCode {
            role = .command
            key = commandKey
        } else {
            return false
        }

        let nowPressed = flags.contains(key.flag)
        let wasPressed = pressed.contains(keyCode)
        guard nowPressed != wasPressed else { return false }

        if nowPressed {
            pressed.insert(keyCode)
            onPress?(role)
        } else {
            pressed.remove(keyCode)
            onRelease?(role)
        }

        return key.shouldConsumeEvent
    }
}
