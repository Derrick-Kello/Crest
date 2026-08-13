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

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        Task { await CommandBarService.shared.loadAppsIfNeeded() }
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func existingOrNewPanel() -> CommandBarPanel {
        if let panel { return panel }

        let panel = CommandBarPanel(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 76),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = true
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

        self.panel = panel
        return panel
    }

    /// Grows downward from the top edge as results appear, so the search field
    /// stays put instead of the whole panel drifting up the screen.
    private func resize(to height: CGFloat) {
        guard let panel, panel.isVisible else { return }
        var frame = panel.frame
        let delta = height - frame.height
        guard abs(delta) > 0.5 else { return }
        frame.origin.y -= delta
        frame.size.height = height
        panel.setFrame(frame, display: true)
    }
}
