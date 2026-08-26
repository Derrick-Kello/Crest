//
//  UserHotKeyService.swift
//  Crest
//

import AppKit
import Foundation

/// Owns the shortcuts the user assigned to individual apps and Crest actions.
///
/// Registration goes through the same Carbon path as the command bar's own
/// shortcut, so none of this needs Accessibility permission. What this adds on top
/// is the bookkeeping: one shortcut per target, conflicts reported rather than
/// silently dropped, and re-registration whenever the list changes.
@MainActor
@Observable
final class UserHotKeyService {
    static let shared = UserHotKeyService()

    private(set) var hotKeys: [UserHotKey] = []
    /// Targets whose shortcut the system refused, so the settings row can say so
    /// instead of the shortcut just not working.
    private(set) var failedIdentifiers: Set<String> = []

    /// Routed back to the view model, which is the only thing that can run a
    /// Crest action. Set once at launch.
    var performAction: ((String) -> Void)?

    private init() {
        hotKeys = Preferences.userHotKeys
    }

    // MARK: - Editing

    /// Adds or replaces the shortcut for `target`.
    ///
    /// Returns false when another target already holds the combination, which is
    /// worth refusing rather than allowing: two registrations of the same key
    /// means only one of them ever fires, and which one is not something the user
    /// could reason about.
    @discardableResult
    func assign(_ combo: HotKeyCombo, to target: HotKeyTarget, name: String, symbolName: String? = nil) -> Bool {
        let identifier = UserHotKey.identifier(for: target)
        guard !hotKeys.contains(where: { $0.id != identifier && $0.combo == combo }) else { return false }
        guard combo != Preferences.commandBarHotKey else { return false }

        let entry = UserHotKey(target: target, name: name, symbolName: symbolName, combo: combo)
        if let index = hotKeys.firstIndex(where: { $0.id == identifier }) {
            hotKeys[index] = entry
        } else {
            hotKeys.append(entry)
        }
        persistAndReregister()
        return true
    }

    func remove(_ hotKey: UserHotKey) {
        HotKeyService.shared.unregister(name: hotKey.registrationName)
        hotKeys.removeAll { $0.id == hotKey.id }
        failedIdentifiers.remove(hotKey.id)
        persistAndReregister()
    }

    func setEnabled(_ isEnabled: Bool, for hotKey: UserHotKey) {
        guard let index = hotKeys.firstIndex(where: { $0.id == hotKey.id }) else { return }
        hotKeys[index].isEnabled = isEnabled
        persistAndReregister()
    }

    /// True when `combo` is already spoken for, so the recorder can say so before
    /// the user commits to it.
    func conflict(for combo: HotKeyCombo, excluding target: HotKeyTarget?) -> String? {
        if combo == Preferences.commandBarHotKey { return "the command bar" }
        let identifier = target.map(UserHotKey.identifier(for:))
        return hotKeys.first { $0.id != identifier && $0.combo == combo }?.name
    }

    // MARK: - Registration

    /// Called at launch and after every edit. Registering is cheap and idempotent
    /// — each call unregisters the previous claim first — so the whole list is
    /// rebuilt rather than diffed.
    func registerAll() {
        failedIdentifiers = []
        for hotKey in hotKeys {
            HotKeyService.shared.unregister(name: hotKey.registrationName)
            guard hotKey.isEnabled else { continue }

            let target = hotKey.target
            let registered = HotKeyService.shared.register(hotKey.combo, name: hotKey.registrationName) { [weak self] in
                self?.fire(target)
            }
            if !registered { failedIdentifiers.insert(hotKey.id) }
        }
    }

    func unregisterAll() {
        for hotKey in hotKeys {
            HotKeyService.shared.unregister(name: hotKey.registrationName)
        }
    }

    private func persistAndReregister() {
        Preferences.userHotKeys = hotKeys
        registerAll()
    }

    // MARK: - Firing

    private func fire(_ target: HotKeyTarget) {
        switch target {
        case .app(let path):
            toggleApp(at: path)
        case .action(let id):
            performAction?(id)
        }
    }

    /// Brings the app forward, or hides it when it is already the frontmost one.
    ///
    /// The hide half is what makes a per-app shortcut worth having: the same key
    /// that summons your terminal puts it away again, so it behaves like a drawer
    /// rather than a launch button that does nothing on the second press.
    private func toggleApp(at path: String) {
        let url = URL(fileURLWithPath: path)
        let running = NSWorkspace.shared.runningApplications.first {
            $0.bundleURL?.standardizedFileURL == url.standardizedFileURL
        }

        if let running, running.isActive {
            running.hide()
            return
        }
        if let running, !running.isTerminated {
            running.unhide()
            running.activate(options: [.activateAllWindows])
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }
}
