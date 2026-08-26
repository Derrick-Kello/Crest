//
//  AppActivation.swift
//  Crest
//

import AppKit

/// Reference-counts the app's activation policy.
///
/// Crest is an `LSUIElement` and stays one, because a Dock icon for a menu-bar
/// app is clutter. But an accessory app cannot reliably make itself frontmost, so
/// anything that needs the keyboard — the command bar, onboarding — has to become
/// `.regular` for as long as it is on screen.
///
/// Counting rather than setting: with two of them open, whichever closed first
/// used to drop the whole app back to `.accessory` and take the keyboard away from
/// the one still showing.
@MainActor
enum AppActivation {
    private static var holders: Set<String> = []

    /// Becomes a regular, activatable app and brings it forward.
    static func beginForeground(_ reason: String) {
        holders.insert(reason)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Drops back to menu-bar-only once nothing else needs the foreground.
    static func endForeground(_ reason: String) {
        holders.remove(reason)
        guard holders.isEmpty else { return }
        NSApp.setActivationPolicy(.accessory)
    }
}
