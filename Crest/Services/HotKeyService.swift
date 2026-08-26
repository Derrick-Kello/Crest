//
//  HotKeyService.swift
//  Crest
//

import AppKit
import Carbon.HIToolbox
import Foundation

/// A system-wide keyboard shortcut.
struct HotKeyCombo: Codable, Sendable, Hashable {
    var keyCode: UInt32
    var modifiers: UInt32

    /// ⌥Space — close to Spotlight's ⌘Space without colliding with it.
    static let `default` = HotKeyCombo(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey))

    /// Builds a combo from a recorded key event, or nil when the event carries no
    /// modifier the system would let us claim.
    ///
    /// A bare key is rejected on purpose: registering `G` globally would swallow
    /// the letter in every text field on the Mac. Shift alone is rejected for the
    /// same reason — `⇧G` is just a capital G.
    init?(event: NSEvent) {
        let carbon = Self.carbonModifiers(from: event.modifierFlags)
        let requiresRealModifier = UInt32(cmdKey | optionKey | controlKey)
        guard carbon & requiresRealModifier != 0 else { return nil }
        self.keyCode = UInt32(event.keyCode)
        self.modifiers = carbon
    }

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Carbon wants its own modifier constants, not `NSEvent`'s bit field.
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        return result
    }

    /// Modifier order follows Apple's own: ⌃⌥⇧⌘, then the key.
    var displayString: String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        parts.append(Self.keyName(for: keyCode))
        return parts.joined()
    }

    /// The whole ANSI layout plus the keys people actually bind, so a recorded
    /// shortcut reads back as what was pressed rather than "Key 40".
    ///
    /// Deliberately a table rather than `UCKeyTranslate` against the live layout:
    /// the hot key registration is by physical key code, so showing the letter
    /// printed on a Dvorak user's key would name something the shortcut does not
    /// actually respond to.
    static func keyName(for keyCode: UInt32) -> String {
        if let named = specialKeyNames[Int(keyCode)] { return named }
        if let letter = ansiKeyNames[Int(keyCode)] { return letter }
        return "Key \(keyCode)"
    }

    private static let specialKeyNames: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦", kVK_Escape: "⎋", kVK_Home: "↖", kVK_End: "↘",
        kVK_PageUp: "⇞", kVK_PageDown: "⇟", kVK_LeftArrow: "←", kVK_RightArrow: "→",
        kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_ANSI_KeypadEnter: "⌤",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5",
        kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10",
        kVK_F11: "F11", kVK_F12: "F12",
    ]

    private static let ansiKeyNames: [Int: String] = [
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D",
        kVK_ANSI_E: "E", kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H",
        kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
        kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P",
        kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
        kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
        kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
        kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7",
        kVK_ANSI_8: "8", kVK_ANSI_9: "9",
        kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=", kVK_ANSI_LeftBracket: "[",
        kVK_ANSI_RightBracket: "]", kVK_ANSI_Backslash: "\\",
        kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'", kVK_ANSI_Comma: ",",
        kVK_ANSI_Period: ".", kVK_ANSI_Slash: "/", kVK_ANSI_Grave: "`",
    ]
}

/// Registers global hot keys through Carbon's `RegisterEventHotKey`.
///
/// Chosen over an `NSEvent` global monitor because it needs no Accessibility
/// permission — the OS delivers the event to us directly rather than us watching
/// every keystroke on the system, which is both a smaller ask of the user and a
/// smaller surface to get wrong.
@MainActor
final class HotKeyService {
    static let shared = HotKeyService()

    private var registrations: [UInt32: (ref: EventHotKeyRef?, handler: () -> Void)] = [:]
    private var eventHandler: EventHandlerRef?
    private var nextID: UInt32 = 1

    private init() {}

    /// Registers `combo`, replacing any previous registration under `name`.
    /// Returns false when the combination is already claimed by another app.
    @discardableResult
    func register(_ combo: HotKeyCombo, name: String, handler: @escaping () -> Void) -> Bool {
        unregister(name: name)
        installHandlerIfNeeded()

        let id = nextID
        nextID += 1
        identifiers[name] = id

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(
            combo.keyCode,
            combo.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )

        guard status == noErr else {
            identifiers.removeValue(forKey: name)
            return false
        }

        registrations[id] = (ref, handler)
        return true
    }

    func unregister(name: String) {
        guard let id = identifiers.removeValue(forKey: name),
              let registration = registrations.removeValue(forKey: id) else { return }
        if let ref = registration.ref { UnregisterEventHotKey(ref) }
    }

    fileprivate func fire(id: UInt32) {
        registrations[id]?.handler()
    }

    private var identifiers: [String: UInt32] = [:]
    private static let signature: OSType = 0x43_52_53_54 // 'CRST'

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
                )
                guard status == noErr, hotKeyID.signature == HotKeyService.signature else { return noErr }
                // The Carbon callback is a bare C function pointer with no context,
                // so the hop back onto the main actor happens here.
                let id = hotKeyID.id
                Task { @MainActor in HotKeyService.shared.fire(id: id) }
                return noErr
            },
            1,
            &spec,
            nil,
            &eventHandler
        )
    }
}
