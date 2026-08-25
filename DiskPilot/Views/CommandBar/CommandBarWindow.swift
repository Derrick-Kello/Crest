//
//  CommandBarWindow.swift
//  DiskPilot
//

import AppKit
import SwiftUI

/// A borderless floating panel that can take keyboard focus.
///
/// `NSPanel` rather than a SwiftUI `Window` scene because the command bar has to
/// behave like Spotlight: no title bar, centred above everything, key without the
/// app owning a normal window, and gone the moment focus leaves.
final class CommandBarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class CommandBarController {
    static let shared = CommandBarController()

    private var panel: CommandBarPanel?
    private var onExecute: ((CommandEntry) -> Void)?
    private var resignObserver: NSObjectProtocol?

    private init() {}

    var isVisible: Bool { panel?.isVisible ?? false }

    func configure(onExecute: @escaping (CommandEntry) -> Void) {
        self.onExecute = onExecute
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        let panel = existingOrNewPanel()

        // Centre horizontally, sit about a third down — where the eye already is,
        // and clear of the menu bar.
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(
                x: frame.midX - size.width / 2,
                y: frame.midY + frame.height / 6
            ))
        }

        activateForTyping(panel)
        // Normally a no-op: the index is built at launch. This only covers the
        // case where the very first open beats the background scan.
        CommandBarService.shared.buildIndex()
    }

    func hide() {
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
            self.resignObserver = nil
        }
        panel?.orderOut(nil)
        // Back to menu-bar-only: no Dock icon, no app-switcher entry.
        NSApp.setActivationPolicy(.accessory)
        // Released rather than cached. Rebuilding costs well under a frame, and a
        // fresh view is the only reliable way to get `onAppear` to run again —
        // which is what clears the previous query and puts focus back in the field.
        // It also means a closed command bar holds no views at all.
        panel = nil
    }

    /// Brings the app forward so the search field actually receives keystrokes.
    ///
    /// An `LSUIElement` app cannot reliably make itself frontmost: measured with
    /// the panel on screen, the process reported `frontmost = false` and every
    /// keystroke went to the app the user came from, so the bar looked fine and
    /// silently ignored typing. Becoming `.regular` makes the app eligible to
    /// activate; `hide()` restores `.accessory`, so the Dock icon exists only for
    /// as long as the bar is open.
    private func activateForTyping(_ panel: CommandBarPanel) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func existingOrNewPanel() -> CommandBarPanel {
        if let panel { return panel }

        // Deliberately NOT `.nonactivatingPanel`: that style keeps the owning app
        // from becoming active, so with `LSUIElement` the panel drew on screen
        // while keystrokes kept going to whatever app was in front — the bar looked
        // fine and simply ignored everything typed into it.
        let panel = CommandBarPanel(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 76),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        // Must stay false: dismissal is handled explicitly on resign-key. With it
        // true, the brief deactivation during activation would hide the panel the
        // instant it appeared.
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.animationBehavior = .utilityWindow

        let view = CommandBarView(
            onExecute: { [weak self] entry in
                self?.hide()
                self?.onExecute?(entry)
            },
            onDismiss: { [weak self] in self?.hide() },
            onHeightChange: { [weak self] height in
                self?.resize(to: height)
            }
        )

        let hosting = NSHostingView(rootView: view)
        hosting.frame = panel.contentRect(forFrameRect: panel.frame)
        panel.contentView = hosting

        // `hidesOnDeactivate` is off, so clicking away has to be handled here or
        // the bar would stay on screen after the user moved on.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }

        self.panel = panel
        return panel
    }

    /// Grows downward from the top edge as results appear, so the search field
    /// stays put instead of the whole panel drifting up the screen.
    private func resize(to height: CGFloat) {
        // Deferred by one runloop pass: this is called from SwiftUI's layout via
        // `onGeometryChange`, and resizing the window in the middle of that leaves
        // the hosting view's backing store showing the previous result list — the
        // rows lag a keystroke behind what the field says.
        DispatchQueue.main.async { [weak self] in
            guard let panel = self?.panel, panel.isVisible else { return }
            var frame = panel.frame
            let delta = height - frame.height
            guard abs(delta) > 0.5 else { return }
            frame.origin.y -= delta
            frame.size.height = height
            panel.setFrame(frame, display: true)
            panel.contentView?.needsDisplay = true
        }
    }
}
