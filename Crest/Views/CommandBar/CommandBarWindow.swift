//
//  CommandBarWindow.swift
//  Crest
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
    /// The size SwiftUI last asked for. The view lays out and reports its size
    /// before the panel is on screen, and a resize applied to a hidden panel used
    /// to be dropped — which left the bar open at its bare field height with the
    /// whole result list clipped off below the bottom edge.
    private var pendingSize: CGSize?

    /// The panel's collapsed height: the search field and nothing else.
    private static let fieldOnlyHeight: CGFloat = 58
    private static let width: CGFloat = CommandBarView.baseWidth

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

        // Centre horizontally on the screen holding the pointer — on a two-display
        // desk, `NSScreen.main` is the one with keyboard focus, which is where the
        // user is looking. Sits about a third down, clear of the menu bar.
        let screen = screenUnderPointer() ?? NSScreen.main
        if let screen {
            let visible = screen.visibleFrame
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(
                x: visible.midX - size.width / 2,
                y: visible.midY + visible.height / 6
            ))
        }

        activateForTyping(panel)
        // Any size the view reported while the panel was still hidden is applied
        // now that it can actually take effect.
        if let pendingSize {
            apply(size: pendingSize, to: panel)
            self.pendingSize = nil
        }
        // Normally a no-op: the catalog is built at launch. This only covers the
        // case where the very first open beats the background scan.
        CommandBarService.shared.buildIndex()
    }

    private func screenUnderPointer() -> NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(location) }
    }

    func hide() {
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
            self.resignObserver = nil
        }
        panel?.orderOut(nil)
        pendingSize = nil
        // Back to menu-bar-only: no Dock icon, no app-switcher entry — unless
        // something else on screen still needs the foreground.
        AppActivation.endForeground("commandBar")
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
        AppActivation.beginForeground("commandBar")
        panel.makeKeyAndOrderFront(nil)
    }

    private func existingOrNewPanel() -> CommandBarPanel {
        if let panel { return panel }

        // `.titled` with its chrome hidden, NOT `.borderless`. A borderless panel
        // looks identical and misbehaves in two ways that both showed up here: the
        // SwiftUI text field rendered keystrokes without ever writing them back
        // through its binding, and the SwiftUI content stopped repainting
        // altogether — the search field updated because AppKit draws it directly,
        // while the result list below stayed frozen on its first frame even as the
        // panel resized around it. Titled fixes both; the chrome is hidden below.
        //
        // Deliberately NOT `.nonactivatingPanel`: that style keeps the owning app
        // from becoming active, so with `LSUIElement` the panel drew on screen
        // while keystrokes kept going to whatever app was in front.
        let panel = CommandBarPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: Self.fieldOnlyHeight),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
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
        // A titled window is draggable by its titlebar, which here is the search
        // field. Nudging the bar off-centre while reaching for the mouse is not a
        // gesture anyone wants, so it stays put.
        panel.isMovable = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.animationBehavior = .utilityWindow

        let view = CommandBarView(
            onExecute: { [weak self] entry in
                self?.hide()
                self?.onExecute?(entry)
            },
            onDismiss: { [weak self] in self?.hide() },
            onSizeChange: { [weak self] size in
                self?.resize(to: size)
            }
        )

        // `contentViewController` rather than assigning a manually-framed
        // `NSHostingView` to `contentView`. With the bare hosting view, SwiftUI
        // re-evaluated the body — verified with a log in the refresh path, which
        // showed the new result rows being built on every keystroke — but the
        // drawn output never changed: the field updated because AppKit draws it,
        // while the SwiftUI list below stayed frozen on whatever it rendered
        // first. Letting the controller own the view fixes the update path, and
        // resizes the content with the panel for free.
        let controller = NSHostingController(rootView: view)
        controller.view.frame = panel.contentRect(forFrameRect: panel.frame)
        panel.contentViewController = controller

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
    private func resize(to size: CGSize) {
        // Deferred by one runloop pass: this is called from inside SwiftUI's
        // layout, and resizing the window in the middle of that leaves the hosting
        // view's backing store showing the previous result list — the rows lag a
        // keystroke behind what the field says.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard let panel = self.panel else {
                self.pendingSize = size
                return
            }
            // Recorded whether or not it can be applied yet, so `show()` can put
            // the panel at the right size the moment it appears rather than
            // flashing at field height and growing a frame later.
            self.pendingSize = size
            guard panel.isVisible else { return }
            self.apply(size: size, to: panel)
            self.pendingSize = nil
        }
    }

    /// Grows downward from the top edge, so the search field stays where the user
    /// is looking instead of the whole panel drifting up the screen as results
    /// appear. Width grows outward from the centre for the same reason: the
    /// preview pane appearing should not slide the search field sideways under the
    /// cursor. Clamped to the screen so a long list cannot run off the bottom.
    private func apply(size: CGSize, to panel: CommandBarPanel) {
        var frame = panel.frame
        let screen = panel.screen ?? NSScreen.main
        let maximumHeight = screen.map { $0.visibleFrame.height - 40 } ?? size.height
        let target = CGSize(width: size.width, height: min(size.height, maximumHeight))

        let deltaHeight = target.height - frame.height
        let deltaWidth = target.width - frame.width
        guard abs(deltaHeight) > 0.5 || abs(deltaWidth) > 0.5 else { return }

        frame.origin.y -= deltaHeight
        frame.origin.x -= deltaWidth / 2
        frame.size = target

        // Widening near a screen edge would otherwise put half the preview pane
        // off the display, where it is not much use.
        if let visible = screen?.visibleFrame {
            frame.origin.x = min(max(frame.origin.x, visible.minX + 8), visible.maxX - frame.width - 8)
        }
        panel.setFrame(frame, display: true)
        panel.contentView?.needsDisplay = true
    }
}
