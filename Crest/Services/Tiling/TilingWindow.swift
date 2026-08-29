//
//  TilingWindow.swift
//  Crest
//

import AppKit
import ApplicationServices

/// One window the tiler knows about.
///
/// The `AXUIElement` is the handle we act through and the `CGWindowID` is the
/// identity we remember — they are separate on purpose. Accessibility hands out a
/// fresh, non-equal element for the same window on a later pass, so an element
/// cannot be a dictionary key or a workspace membership; the window id can.
nonisolated struct TilingWindow: Identifiable, Hashable {
    let id: CGWindowID
    let element: AXUIElement
    let pid: pid_t
    let appName: String
    let bundleID: String?
    let title: String

    static func == (lhs: TilingWindow, rhs: TilingWindow) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var frame: CGRect? { AX.frame(of: element) }

    /// Brings this window forward and gives it keyboard focus.
    ///
    /// Two steps, because they do different things and neither is sufficient:
    /// raising orders the window to the front within its own application, and
    /// activating brings that application in front of every other one. Raise alone
    /// leaves focus behind in the app you came from.
    func focus() {
        AX.set(element, kAXMainAttribute as String, kCFBooleanTrue)
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        NSRunningApplication(processIdentifier: pid)?.activate()
    }

    func close() {
        guard let button = AX.element(element, kAXCloseButtonAttribute as String) else { return }
        AXUIElementPerformAction(button, kAXPressAction as CFString)
    }
}

/// Finds the windows on the system that a tiler is allowed to move.
nonisolated enum WindowEnumerator {

    /// Bundle identifiers whose windows are never tiled.
    ///
    /// Not a matter of taste. These either refuse to be resized at all, or they
    /// are chrome that happens to be shaped like a window — moving them produces a
    /// gap in the layout where a window should be, or a visibly broken desktop.
    static let neverTile: Set<String> = [
        "com.apple.systempreferences",
        "com.apple.finder.SaveDialog",
        "com.apple.dock",
        "com.apple.notificationcenterui",
        "com.apple.controlcenter",
        "com.apple.Spotlight",
        "com.apple.screencaptureui",
        "com.apple.loginwindow",
        "com.apple.WindowManager",
        "com.apple.PowerChime",
        // Crest's own bundle id, matched exactly as the project spells it. A
        // lowercased copy of this string silently fails to match, and the only
        // thing standing between that and Crest tiling its own settings window is
        // the accessory activation policy — which is not a guarantee worth
        // resting on.
        "com.smarthive.Crest",
    ]

    /// Every standard, visible, resizable window on the system.
    ///
    /// Each attribute read is a synchronous IPC round trip into the owning app, so
    /// a single unresponsive application would otherwise hang the whole layout
    /// pass. The messaging timeout below caps that: a beachballing app costs a
    /// quarter second and drops out of the layout, rather than freezing Crest.
    static func current(extraExcludedBundleIDs: Set<String> = []) -> [TilingWindow] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var results: [TilingWindow] = []

        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular,
                  app.processIdentifier != ownPID,
                  !app.isTerminated
            else { continue }

            let bundleID = app.bundleIdentifier
            if let bundleID, neverTile.contains(bundleID) || extraExcludedBundleIDs.contains(bundleID) { continue }

            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(axApp, 0.25)

            for window in AX.elements(axApp, kAXWindowsAttribute as String) {
                guard isTileable(window),
                      let id = AX.windowID(of: window)
                else { continue }

                results.append(TilingWindow(
                    id: id,
                    element: window,
                    pid: app.processIdentifier,
                    appName: app.localizedName ?? "Unknown",
                    bundleID: bundleID,
                    title: AX.copy(window, kAXTitleAttribute as String) ?? ""
                ))
            }
        }
        return results
    }

    /// The window that currently has keyboard focus, if the tiler manages it.
    static func focused() -> CGWindowID? {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, 0.25)
        guard let app = AX.element(systemWide, kAXFocusedApplicationAttribute as String),
              let window = AX.element(app, kAXFocusedWindowAttribute as String)
        else { return nil }
        return AX.windowID(of: window)
    }

    /// A window is tiled when it is a real, ordinary, on-screen window.
    ///
    /// The subrole check is what separates a document window from the sheets,
    /// popovers, tooltips and system dialogs that share the window role. Tiling
    /// those is the difference between a window manager and a program that drags a
    /// colour picker into the corner of your screen.
    private static func isTileable(_ window: AXUIElement) -> Bool {
        guard let subrole: String = AX.copy(window, kAXSubroleAttribute as String),
              subrole == kAXStandardWindowSubrole as String
        else { return false }

        if let minimized: Bool = AX.copy(window, kAXMinimizedAttribute as String), minimized { return false }

        // A window that will not accept a new size cannot be laid out, and trying
        // anyway leaves it overlapping whatever the layout put beside it.
        guard AX.isSettable(window, kAXPositionAttribute as String),
              AX.isSettable(window, kAXSizeAttribute as String)
        else { return false }

        // Zero-sized and hairline windows are the offscreen helpers that several
        // Electron and Java apps keep permanently open.
        guard let frame = AX.frame(of: window), frame.width > 80, frame.height > 80 else { return false }

        return true
    }
}

/// Screen rectangles in the coordinate space the Accessibility API expects.
///
/// The two frameworks disagree about which way is up. `NSScreen` puts the origin
/// at the bottom-left of the primary display with y growing upward; Accessibility
/// puts it at the top-left with y growing downward. Reading a frame in one space
/// and writing it in the other is the single most common way a macOS tiler ends up
/// throwing windows off the bottom of the screen, so the conversion happens here
/// and nowhere else.
nonisolated enum Display {

    /// Height of the display that defines the origin, which is the one whose
    /// Cocoa frame starts at zero — not necessarily `NSScreen.main`, which follows
    /// the key window and moves between monitors.
    private static var primaryHeight: CGFloat {
        NSScreen.screens.first { $0.frame.origin == .zero }?.frame.height
            ?? NSScreen.screens.first?.frame.height
            ?? 0
    }

    static func toAX(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: primaryHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    /// The usable area of a screen in AX coordinates: the full frame minus the
    /// menu bar and the Dock, which is what `visibleFrame` already accounts for.
    static func usableFrame(of screen: NSScreen) -> CGRect {
        toAX(screen.visibleFrame)
    }

    /// The screen a window sits on, chosen by greatest overlap so that a window
    /// straddling two monitors belongs to the one showing most of it.
    static func screen(containing axFrame: CGRect) -> NSScreen? {
        NSScreen.screens.max { left, right in
            toAX(left.frame).intersection(axFrame).area < toAX(right.frame).intersection(axFrame).area
        }
    }

    /// Where windows go to be invisible.
    ///
    /// Switching workspaces has to hide windows, and macOS gives no way to do that
    /// without side effects: minimising animates and drops them into the Dock,
    /// `NSRunningApplication.hide()` acts on a whole app rather than one window,
    /// and real Spaces cannot be scripted without disabling SIP. Parking a window
    /// far off the right edge of the desktop is instant, reversible, invisible to
    /// the user, and leaves the window fully live — ⌘-Tab and the Dock still reach
    /// it. It is what AeroSpace does, for the same reasons.
    static func parkingSpot(for size: CGSize) -> CGRect {
        let right = NSScreen.screens.map { toAX($0.frame).maxX }.max() ?? 2000
        return CGRect(x: right + 200, y: 0, width: size.width, height: size.height)
    }

    static func isParked(_ frame: CGRect) -> Bool {
        let right = NSScreen.screens.map { toAX($0.frame).maxX }.max() ?? 2000
        return frame.origin.x >= right + 100
    }
}

private extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }
}
