//
//  HotKeyService.swift
//  DiskPilot
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

    var displayString: String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        parts.append(Self.keyName(for: keyCode))
        return parts.joined()
    }

    private static func keyName(for keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_Space: "Space"
        case kVK_Return: "↩"
        case kVK_Tab: "⇥"
        case kVK_ANSI_Period: "."
        case kVK_ANSI_Comma: ","
        case kVK_ANSI_Slash: "/"
        case kVK_ANSI_D: "D"
        case kVK_ANSI_K: "K"
        case kVK_ANSI_V: "V"
        case kVK_ANSI_C: "C"
        default: "Key \(keyCode)"
        }
    }
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
    private static let signature: OSType = 0x44_53_4B_50 // 'DSKP'

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
