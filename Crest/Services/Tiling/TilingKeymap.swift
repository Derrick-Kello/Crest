//
//  TilingKeymap.swift
//  Crest
//

import Carbon.HIToolbox
import Foundation

/// One tiling command and the key that runs it.
nonisolated struct TilingBinding: Identifiable, Codable, Sendable, Hashable {
    let id: String
    let title: String
    let group: String
    var combo: HotKeyCombo

    var registrationName: String { "tiling:" + id }
}

/// Which modifier stands in for Omarchy's SUPER key.
///
/// Configurable rather than fixed, because there is no modifier on a Mac that is
/// free for everyone. ⌘ is out permanently: ⌘W, ⌘Q, ⌘H and ⌘1 through ⌘9 all mean
/// something in every application, and claiming them globally would break the Mac
/// to make it behave like Linux. That leaves the others, and which of them is
/// actually free depends on what else the user has bound — Crest's own dictation
/// key being the obvious example.
///
/// Shift is deliberately absent from every case. It is the second level of the map
/// (`mod` focuses a window, `mod`+⇧ moves it), so a base modifier containing Shift
/// would have nothing left to build the move half out of. Shift alone is worse
/// still: ⇧1 is `!` and ⇧H is `H`, so registering those globally would swallow
/// capital letters and the whole number row in every text field on the system.
nonisolated enum TilingModifier: String, Codable, CaseIterable, Sendable, Identifiable {
    /// ⌘⌃. The safest pair on macOS, and the default for that reason.
    case commandControl
    /// ⌃ alone. One key, closest in feel to a real SUPER, but ⌃H and ⌃K are
    /// backspace and kill-line in every macOS text field.
    case control
    /// ⌥ alone. The nicest to type and the most likely to be already taken, since
    /// Crest's own push-to-talk dictation defaults to right ⌥.
    case option
    /// ⌃⌥. Free in practice, at the cost of two keys.
    case controlOption

    var id: String { rawValue }

    var carbonValue: UInt32 {
        switch self {
        case .commandControl: UInt32(cmdKey | controlKey)
        case .control: UInt32(controlKey)
        case .option: UInt32(optionKey)
        case .controlOption: UInt32(controlKey | optionKey)
        }
    }

    var symbols: String {
        switch self {
        case .commandControl: "⌃⌘"
        case .control: "⌃"
        case .option: "⌥"
        case .controlOption: "⌃⌥"
        }
    }

    /// What the user gives up by choosing this one. Shown in settings, because
    /// every option here costs something and picking blind means finding out by
    /// losing a shortcut you use.
    var caution: String? {
        switch self {
        case .commandControl: nil
        case .control: "⌃H and ⌃K are backspace and kill-line in macOS text fields, and ⌃1 through ⌃9 may already switch Spaces."
        case .option: "Clashes with Crest's own dictation key if that is set to ⌥, and with the ⌥ characters some layouts type."
        case .controlOption: nil
        }
    }
}

/// The key map, and the rules behind it.
///
/// Follows Omarchy key for key. The modifier is whatever the user picked; the
/// second level is always that plus Shift.
///
/// The command bar's own shortcut is left alone whatever the modifier, because
/// `TilingHotKeyService` refuses to bind over it.
nonisolated enum TilingKeymap {

    /// Built against a modifier rather than stored, so changing the setting
    /// rebuilds the whole map instead of leaving half of it on the old key.
    static func defaults(modifier: TilingModifier) -> [TilingBinding] {
        let mod = modifier.carbonValue
        let modShift = mod | UInt32(shiftKey)
        return focusBindings(mod, modShift)
            + moveBindings(mod, modShift)
            + workspaceBindings(mod, modShift)
            + layoutBindings(mod)
            + windowBindings(mod, modShift)
    }

    // MARK: - Focus

    /// hjkl as on Omarchy, with the arrow keys bound to the same commands so the
    /// map is usable before the vim keys are in your fingers.
    private static func focusBindings(_ mod: UInt32, _ modShift: UInt32) -> [TilingBinding] { [
        binding("focus.left", "Focus left", "Focus", kVK_ANSI_H, mod),
        binding("focus.down", "Focus down", "Focus", kVK_ANSI_J, mod),
        binding("focus.up", "Focus up", "Focus", kVK_ANSI_K, mod),
        binding("focus.right", "Focus right", "Focus", kVK_ANSI_L, mod),
        binding("focus.left.arrow", "Focus left", "Focus", kVK_LeftArrow, mod),
        binding("focus.down.arrow", "Focus down", "Focus", kVK_DownArrow, mod),
        binding("focus.up.arrow", "Focus up", "Focus", kVK_UpArrow, mod),
        binding("focus.right.arrow", "Focus right", "Focus", kVK_RightArrow, mod),
        binding("focus.next", "Focus next window", "Focus", kVK_ANSI_Grave, mod),
        binding("focus.previous", "Focus previous window", "Focus", kVK_ANSI_Grave, modShift),
    ] }

    // MARK: - Moving windows

    private static func moveBindings(_ mod: UInt32, _ modShift: UInt32) -> [TilingBinding] { [
        binding("swap.left", "Move window left", "Move", kVK_ANSI_H, modShift),
        binding("swap.down", "Move window down", "Move", kVK_ANSI_J, modShift),
        binding("swap.up", "Move window up", "Move", kVK_ANSI_K, modShift),
        binding("swap.right", "Move window right", "Move", kVK_ANSI_L, modShift),
        binding("swap.left.arrow", "Move window left", "Move", kVK_LeftArrow, modShift),
        binding("swap.down.arrow", "Move window down", "Move", kVK_DownArrow, modShift),
        binding("swap.up.arrow", "Move window up", "Move", kVK_UpArrow, modShift),
        binding("swap.right.arrow", "Move window right", "Move", kVK_RightArrow, modShift),
        binding("promote", "Make window the main pane", "Move", kVK_Return, modShift),
    ] }

    // MARK: - Workspaces

    private static func workspaceBindings(_ mod: UInt32, _ modShift: UInt32) -> [TilingBinding] {
        let digits = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
                      kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]
        var result: [TilingBinding] = []

        for (offset, key) in digits.enumerated() {
            let number = offset + 1
            result.append(binding("workspace.\(number)", "Workspace \(number)", "Workspaces", key, mod))
            result.append(binding("workspace.move.\(number)", "Send window to workspace \(number)", "Workspaces", key, modShift))
        }
        result.append(binding("workspace.previous", "Previous workspace", "Workspaces", kVK_ANSI_LeftBracket, mod))
        result.append(binding("workspace.next", "Next workspace", "Workspaces", kVK_ANSI_RightBracket, mod))
        return result
    }

    // MARK: - Layout

    private static func layoutBindings(_ mod: UInt32) -> [TilingBinding] { [
        binding("layout.cycle", "Cycle layout", "Layout", kVK_ANSI_E, mod),
        binding("layout.shrink", "Shrink pane", "Layout", kVK_ANSI_Minus, mod),
        binding("layout.grow", "Grow pane", "Layout", kVK_ANSI_Equal, mod),
        binding("layout.main.fewer", "Fewer windows in main pane", "Layout", kVK_ANSI_Comma, mod),
        binding("layout.main.more", "More windows in main pane", "Layout", kVK_ANSI_Period, mod),
        binding("layout.balance", "Balance panes", "Layout", kVK_ANSI_0, mod),
        binding("layout.retile", "Re-tile everything", "Layout", kVK_ANSI_R, mod),
    ] }

    // MARK: - Windows

    private static func windowBindings(_ mod: UInt32, _ modShift: UInt32) -> [TilingBinding] { [
        binding("window.zoom", "Fill the screen", "Window", kVK_ANSI_F, mod),
        binding("window.float", "Float or tile the window", "Window", kVK_ANSI_V, mod),
        binding("window.close", "Close window", "Window", kVK_ANSI_Q, modShift),
        binding("tiling.toggle", "Turn tiling on or off", "Window", kVK_ANSI_T, modShift),
    ] }

    private static func binding(_ id: String, _ title: String, _ group: String, _ key: Int, _ modifiers: UInt32) -> TilingBinding {
        TilingBinding(id: id, title: title, group: group, combo: HotKeyCombo(keyCode: UInt32(key), modifiers: modifiers))
    }

    /// Groups in the order the settings list shows them.
    static let groups = ["Focus", "Move", "Workspaces", "Layout", "Window"]
}
