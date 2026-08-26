//
//  UserHotKey.swift
//  Crest
//

import Foundation

/// What a user-assigned global shortcut does when it fires.
///
/// An app and a Crest action are the same thing from the shortcut's point of
/// view — a target it hands to the runner — so they share one type rather than
/// two parallel lists with two registration paths and two settings tables.
enum HotKeyTarget: Codable, Sendable, Hashable {
    /// Launch the app, or bring it forward when it is already running.
    case app(path: String)
    /// One of `SystemCatalog.actions`, routed through the view model.
    case action(id: String)
}

/// A shortcut the user assigned to one app or action.
///
/// The name and symbol are stored alongside the target rather than looked up when
/// the settings list draws: an app that has since been moved or uninstalled still
/// shows what its shortcut was bound to, which is what lets the user recognise the
/// row well enough to delete it.
struct UserHotKey: Codable, Sendable, Hashable, Identifiable {
    var id: String
    var target: HotKeyTarget
    var name: String
    var symbolName: String?
    var combo: HotKeyCombo
    var isEnabled: Bool

    init(
        target: HotKeyTarget,
        name: String,
        symbolName: String? = nil,
        combo: HotKeyCombo,
        isEnabled: Bool = true
    ) {
        self.id = Self.identifier(for: target)
        self.target = target
        self.name = name
        self.symbolName = symbolName
        self.combo = combo
        self.isEnabled = isEnabled
    }

    /// Derived from the target, so one app can only ever hold one shortcut —
    /// binding a second overwrites the first rather than leaving two rows that
    /// both claim to be the shortcut for Safari.
    static func identifier(for target: HotKeyTarget) -> String {
        switch target {
        case .app(let path): "app:" + path
        case .action(let id): id
        }
    }

    /// The path this shortcut opens, when it opens one. Used to draw the real app
    /// icon in the settings list instead of a generic glyph.
    var appPath: String? {
        if case .app(let path) = target { return path }
        return nil
    }

    /// Name of the registration in `HotKeyService`, which keys by string.
    var registrationName: String { "user:" + id }
}
