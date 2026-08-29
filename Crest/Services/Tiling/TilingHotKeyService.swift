//
//  TilingHotKeyService.swift
//  Crest
//

import Foundation
import Observation

/// Registers the tiling key map and routes each press to the engine.
///
/// Goes through the same Carbon registration as the rest of Crest's shortcuts, so
/// the keys work without Accessibility permission and without watching every
/// keystroke on the machine. Accessibility is needed to *move* the windows, not to
/// hear the key that asked.
@MainActor
@Observable
final class TilingHotKeyService {
    static let shared = TilingHotKeyService()

    /// The live map: defaults, with any combination the user re-recorded applied
    /// over the top.
    private(set) var bindings: [TilingBinding] = []
    /// Bindings the system refused, because another app already holds the key.
    /// Surfaced in settings rather than swallowed — a shortcut that silently does
    /// nothing is the worst version of this bug.
    private(set) var failedIdentifiers: Set<String> = []

    private var isRegistered = false

    private init() {
        bindings = Self.rebuild()
    }

    // MARK: - Registration

    /// Claims the key map.
    ///
    /// While tiling is off, only the shortcut that turns it *on* is registered.
    /// Registering the whole map would be worse in both directions: a global claim
    /// on ⌥H swallows that key everywhere on the Mac, and the user turned tiling
    /// off precisely to stop Crest interfering. Gating the whole map on the
    /// preference instead would make the toggle the one key that could never fire.
    func registerAll() {
        unregisterAll()

        let active = Preferences.tilingEnabled
            ? bindings
            : bindings.filter { $0.id == "tiling.toggle" }

        failedIdentifiers = []
        for binding in active {
            let id = binding.id
            let registered = HotKeyService.shared.register(binding.combo, name: binding.registrationName) {
                Task { @MainActor in TilingHotKeyService.shared.perform(id) }
            }
            if !registered { failedIdentifiers.insert(id) }
        }
        isRegistered = true
    }

    func unregisterAll() {
        guard isRegistered else { return }
        for binding in bindings {
            HotKeyService.shared.unregister(name: binding.registrationName)
        }
        isRegistered = false
    }

    // MARK: - Editing

    /// Rebinds one command. Returns false when the key is already claimed inside
    /// Crest, which is refused rather than allowed: two registrations of one key
    /// means one of them never fires and the user cannot tell which.
    @discardableResult
    func rebind(_ binding: TilingBinding, to combo: HotKeyCombo) -> Bool {
        guard combo != Preferences.commandBarHotKey else { return false }
        guard !bindings.contains(where: { $0.id != binding.id && $0.combo == combo }) else { return false }
        guard UserHotKeyService.shared.conflict(for: combo, excluding: nil) == nil else { return false }

        guard let index = bindings.firstIndex(where: { $0.id == binding.id }) else { return false }
        bindings[index].combo = combo

        var overrides = Preferences.tilingKeyOverrides
        overrides[binding.id] = combo
        Preferences.tilingKeyOverrides = overrides

        registerAll()
        return true
    }

    func resetToDefaults() {
        Preferences.tilingKeyOverrides = [:]
        bindings = Self.rebuild()
        registerAll()
    }

    /// Switches the modifier the whole map hangs off.
    ///
    /// Rebinds every shortcut rather than only the unmodified ones, and drops the
    /// user's per-command overrides on the way. Keeping them would leave a map
    /// where most keys moved to the new modifier and a few stayed on the old one,
    /// which is harder to use than either and impossible to explain.
    func setModifier(_ modifier: TilingModifier) {
        guard modifier != Preferences.tilingModifier else { return }
        Preferences.tilingModifier = modifier
        Preferences.tilingKeyOverrides = [:]
        bindings = Self.rebuild()
        registerAll()
    }

    private static func rebuild() -> [TilingBinding] {
        merged(
            defaults: TilingKeymap.defaults(modifier: Preferences.tilingModifier),
            overrides: Preferences.tilingKeyOverrides
        )
    }

    private static func merged(defaults: [TilingBinding], overrides: [String: HotKeyCombo]) -> [TilingBinding] {
        defaults.map { binding in
            guard let combo = overrides[binding.id] else { return binding }
            var updated = binding
            updated.combo = combo
            return updated
        }
    }

    // MARK: - Dispatch

    /// Maps a binding id onto an engine command.
    ///
    /// A string switch rather than a closure stored on the binding, because the
    /// bindings are `Codable` — they are written to preferences when the user
    /// rebinds one, and a closure cannot be.
    private func perform(_ id: String) {
        let engine = TilingEngine.shared

        if id == "tiling.toggle" {
            engine.toggle()
            registerAll()
            return
        }

        guard engine.isRunning else { return }

        switch id {
        case let id where id.hasPrefix("focus."):
            performFocus(id, engine)
        case let id where id.hasPrefix("swap."):
            if let direction = direction(from: id) { engine.swap(direction) }
        case "promote":
            engine.promoteFocused()
        case let id where id.hasPrefix("workspace."):
            performWorkspace(id, engine)
        case "layout.cycle": engine.cycleLayout()
        case "layout.shrink": engine.resize(by: -0.05)
        case "layout.grow": engine.resize(by: 0.05)
        case "layout.main.fewer": engine.adjustMainCount(by: -1)
        case "layout.main.more": engine.adjustMainCount(by: 1)
        case "layout.balance": engine.balance()
        case "layout.retile": engine.refresh()
        case "window.zoom": engine.toggleZoom()
        case "window.float": engine.toggleFloat()
        case "window.close": engine.closeFocused()
        default: break
        }
    }

    private func performFocus(_ id: String, _ engine: TilingEngine) {
        switch id {
        case "focus.next": engine.focusCycling(forward: true)
        case "focus.previous": engine.focusCycling(forward: false)
        default:
            if let direction = direction(from: id) { engine.focus(direction) }
        }
    }

    private func performWorkspace(_ id: String, _ engine: TilingEngine) {
        switch id {
        case "workspace.next": engine.switchToWorkspaceCycling(forward: true)
        case "workspace.previous": engine.switchToWorkspaceCycling(forward: false)
        default:
            let parts = id.split(separator: ".")
            guard let number = parts.last.flatMap({ Int($0) }) else { return }
            if id.contains(".move.") {
                engine.moveFocused(toWorkspace: number)
            } else {
                engine.switchTo(workspace: number)
            }
        }
    }

    /// `focus.left`, `focus.left.arrow` and `swap.left` all name the same direction.
    private func direction(from id: String) -> TilingDirection? {
        let parts = id.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        return TilingDirection(rawValue: String(parts[1]))
    }
}
