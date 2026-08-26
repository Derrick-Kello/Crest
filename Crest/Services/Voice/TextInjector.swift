//
//  TextInjector.swift
//  Crest
//

import AppKit
import ApplicationServices
import Foundation
import OSLog

/// Puts text into whatever field currently has keyboard focus, and reads back what is
/// selected there.
///
/// Two strategies, in order:
/// 1. **Accessibility** — set `kAXSelectedTextAttribute` on the focused element. Clean,
///    instant, and it leaves the pasteboard untouched.
/// 2. **Pasteboard + ⌘V** — works in Electron apps and anything else with a half-hearted
///    AX implementation. The previous pasteboard contents are restored afterwards.
///
/// The catch that makes this non-obvious: **many apps return `.success` from the AX write
/// and then do nothing.** Electron (Cursor, VS Code, Slack, Discord), Chrome and most
/// terminal emulators all report `kAXSelectedTextAttribute` as settable, accept the
/// write, and silently drop it. So the return value is not evidence of anything —
/// strategy 1 is trusted only when the insertion point can be *observed* to have moved.
///
/// All of this works because the dictation HUD is a non-activating panel: focus never
/// leaves the user's app, so "the focused element" is still their text field.
@MainActor
enum TextInjector {
    enum Outcome: Equatable {
        case inserted
        case pasted
        /// The focused field is a password field. Nothing was typed, deliberately.
        case refusedSecureField
        case noTarget
    }

    @discardableResult
    static func insert(_ text: String) -> Outcome {
        guard !text.isEmpty else { return .noTarget }

        // Dictation into a password field is never what someone meant, and the failure
        // is expensive in both directions: a spoken password ends up in the transcript
        // history, and a half-transcribed one ends up in the field. Neither is
        // recoverable, so this refuses before either can happen.
        if isSecureFieldFocused() {
            VoiceLog.inject.info("refused — focused element is a secure field")
            return .refusedSecureField
        }

        switch insertViaAccessibility(text) {
        case .inserted:
            VoiceLog.inject.info("inserted via AX (\(text.count, privacy: .public) chars)")
            return .inserted
        case .unverified(let reason):
            VoiceLog.inject.info("AX insert not verified (\(reason, privacy: .public)) — pasting")
            insertViaPasteboard(text)
            return .pasted
        }
    }

    /// The bundle identifier of the app the text would land in, used to pick a cleanup
    /// style. Read *before* recording rather than after, because by the time an
    /// utterance finishes the user may have switched apps.
    static func frontmostBundleIdentifier() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    static func frontmostApplicationName() -> String? {
        NSWorkspace.shared.frontmostApplication?.localizedName
    }

    /// What is selected in the focused element, if anything. This is what makes command
    /// mode possible: select a paragraph, hold the key, say "make this shorter".
    static func selectedText() -> String? {
        guard let element = focusedElement() else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXSelectedTextAttribute as CFString, &value
        ) == .success, let value else { return nil }

        let text = value as? String
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return text
    }

    // MARK: - Focus inspection

    private static func focusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedUIElementAttribute as CFString, &focused
        ) == .success, let focused else { return nil }
        return unsafeDowncast(focused as AnyObject, to: AXUIElement.self)
    }

    /// True when the focused element is a password field.
    ///
    /// Checks the role as well as the subrole: `AXSecureTextField` is the role AppKit
    /// reports, while web password inputs come through as an ordinary text field
    /// carrying the secure *subrole*. Missing either one defeats the guard.
    private static func isSecureFieldFocused() -> Bool {
        guard let element = focusedElement() else { return false }

        var role: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success,
           let role = role as? String, role == "AXSecureTextField" {
            return true
        }

        var subrole: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole) == .success,
           let subrole = subrole as? String, subrole == (kAXSecureTextFieldSubrole as String) {
            return true
        }

        return false
    }

    private enum AXOutcome {
        case inserted
        case unverified(String)
    }

    // MARK: - Strategy 1: Accessibility, verified

    private static func insertViaAccessibility(_ text: String) -> AXOutcome {
        guard let element = focusedElement() else {
            return .unverified("no focused element")
        }

        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(
            element, kAXSelectedTextAttribute as CFString, &settable
        ) == .success, settable.boolValue else {
            return .unverified("selected text not settable")
        }

        // Without a readable insertion point there is no way to tell a real insert from
        // a silently dropped one, so don't gamble — go straight to the fallback.
        guard let before = selectedRange(of: element) else {
            return .unverified("no readable selection range")
        }

        guard AXUIElementSetAttributeValue(
            element, kAXSelectedTextAttribute as CFString, text as CFString
        ) == .success else {
            return .unverified("set attribute failed")
        }

        guard let after = selectedRange(of: element) else {
            return .unverified("selection range unreadable after write")
        }

        // Deliberately a *movement* check, not an exact-length one. Falling back after a
        // write that actually landed would paste the text a second time, and a
        // duplicated paragraph is far worse than a missing one. Some apps normalize
        // newlines or run autocorrect, so the caret can legitimately advance by
        // something other than the UTF-16 count — only a completely unmoved selection
        // proves nothing happened.
        let unchanged = after.location == before.location && after.length == before.length
        guard !unchanged else {
            return .unverified("selection unmoved at \(before.location)")
        }

        return .inserted
    }

    private static func selectedRange(of element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString, &value
        ) == .success, let value else { return nil }

        let axValue = unsafeDowncast(value as AnyObject, to: AXValue.self)
        guard AXValueGetType(axValue) == .cfRange else { return nil }

        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range) else { return nil }
        return range
    }

    // MARK: - Strategy 2: Pasteboard + ⌘V

    private static func insertViaPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        let saved = pasteboard.pasteboardItems?.compactMap { item -> [NSPasteboard.PasteboardType: Data] in
            var copy: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { copy[type] = data }
            }
            return copy
        }

        pasteboard.clearContents()
        // Marked transient so Crest's own clipboard history does not record a
        // dictation as something the user copied — the text is already in the voice
        // history, and it would show up twice.
        pasteboard.setString(text, forType: .string)
        pasteboard.setData(Data([1]), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))

        Task { @MainActor in
            // Give the target app a moment to observe the new pasteboard generation
            // before ⌘V arrives, or a fast paste can grab the *previous* contents.
            try? await Task.sleep(for: .milliseconds(40))
            postCommandV()
            VoiceLog.inject.info("pasted (\(text.count, privacy: .public) chars)")

            // The paste is asynchronous in the target app; restore only once it has had
            // time to read the pasteboard.
            try? await Task.sleep(for: .milliseconds(500))
            restore(saved, to: pasteboard)
        }
    }

    private static func postCommandV() {
        guard let source = CGEventSource(stateID: .privateState) else { return }
        let vKey: CGKeyCode = 9 // kVK_ANSI_V

        guard let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        else { return }

        // Set explicitly rather than inheriting live hardware modifier state — the user
        // may still be resting a finger on something.
        down.flags = .maskCommand
        up.flags = .maskCommand

        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private static func restore(
        _ saved: [[NSPasteboard.PasteboardType: Data]]?,
        to pasteboard: NSPasteboard
    ) {
        guard let saved, !saved.isEmpty else { return }
        pasteboard.clearContents()
        let items = saved.map { entry -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in entry { item.setData(data, forType: type) }
            return item
        }
        pasteboard.writeObjects(items)
    }
}
