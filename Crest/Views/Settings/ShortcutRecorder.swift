//
//  ShortcutRecorder.swift
//  Crest
//

import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A field that records the next key combination pressed.
///
/// A picker of pre-chosen combinations was what shipped first, and it is the
/// wrong control for this: the whole value of a per-app shortcut is that it is
/// the one *you* would reach for. Recording needs no Accessibility permission —
/// the monitor is local to this window, not system-wide.
struct ShortcutRecorder: NSViewRepresentable {
    @Binding var combo: HotKeyCombo?
    /// Returns a description of what already owns the combination, or nil when it
    /// is free. Shown in place of the shortcut so a conflict is visible before it
    /// is committed.
    var conflict: (HotKeyCombo) -> String? = { _ in nil }
    var placeholder = "Click to record"

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.onRecord = { recorded in
            combo = recorded
        }
        button.onClear = { combo = nil }
        button.conflictCheck = conflict
        return button
    }

    func updateNSView(_ button: RecorderButton, context: Context) {
        button.onRecord = { recorded in combo = recorded }
        button.onClear = { combo = nil }
        button.conflictCheck = conflict
        button.placeholder = placeholder
        button.combo = combo
    }
}

/// The recorder itself.
///
/// `NSButton` rather than a SwiftUI button with `onKeyPress`: recording has to
/// swallow every key including Tab, Escape and ⌘Q while it is armed, and SwiftUI's
/// key handling lets all three through to the window.
final class RecorderButton: NSButton {
    var onRecord: ((HotKeyCombo) -> Void)?
    var onClear: (() -> Void)?
    var conflictCheck: ((HotKeyCombo) -> String?) = { _ in nil }
    var placeholder = "Click to record"

    var combo: HotKeyCombo? {
        didSet { refreshTitle() }
    }

    private var isRecording = false {
        didSet { refreshTitle() }
    }
    private var monitor: Any?
    private var conflictMessage: String?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(toggleRecording)
        refreshTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    /// Disarms when the view leaves its window.
    ///
    /// `deinit` is not enough on its own: SwiftUI holds a representable's view
    /// alive past the point where it stops being on screen, so a recorder left
    /// armed in a dismissed sheet kept a local monitor installed and went on
    /// swallowing keystrokes — then wrote whatever it caught through a binding
    /// belonging to a screen the user had already left.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stop() }
    }

    @objc private func toggleRecording() {
        isRecording ? stop() : start()
    }

    private func start() {
        guard !isRecording else { return }
        isRecording = true
        conflictMessage = nil

        // Local, so it only sees keys aimed at this app's windows. Returning nil
        // consumes the event, which is what stops ⌘W closing Settings mid-record.
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            // A recorder that is off screen, or whose window is no longer key, has
            // no business claiming the keyboard — the event belongs to whatever
            // the user is actually looking at.
            guard let self, self.isRecording, let window = self.window, window.isKeyWindow else {
                self?.stop()
                return event
            }
            guard event.type == .keyDown else { return nil }

            // Escape abandons the recording rather than becoming the shortcut,
            // which is the only way out once the field is swallowing every key.
            if event.keyCode == UInt16(kVK_Escape),
               HotKeyCombo.carbonModifiers(from: event.modifierFlags) == 0 {
                self.stop()
                return nil
            }
            // Delete clears the binding, matching how every other shortcut field
            // on the Mac behaves.
            if event.keyCode == UInt16(kVK_Delete),
               HotKeyCombo.carbonModifiers(from: event.modifierFlags) == 0 {
                self.stop()
                self.onClear?()
                return nil
            }

            guard let recorded = HotKeyCombo(event: event) else {
                // A bare key: keep listening rather than silently accepting
                // something that cannot be registered system-wide.
                NSSound.beep()
                return nil
            }
            if let owner = self.conflictCheck(recorded) {
                self.conflictMessage = "Already used by \(owner)"
                self.refreshTitle()
                NSSound.beep()
                return nil
            }

            self.stop()
            self.onRecord?(recorded)
            return nil
        }
    }

    private func stop() {
        isRecording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    override func resignFirstResponder() -> Bool {
        stop()
        return super.resignFirstResponder()
    }

    private func refreshTitle() {
        if let conflictMessage {
            title = conflictMessage
            contentTintColor = .systemOrange
            return
        }
        contentTintColor = nil
        if isRecording {
            title = "Press keys…"
        } else if let combo {
            title = combo.displayString
        } else {
            title = placeholder
        }
    }
}
