//
//  TilingEngine.swift
//  Crest
//

import AppKit
import ApplicationServices
import Observation

/// One virtual workspace.
///
/// Membership is by window id and is deliberately *not* persisted: `CGWindowID` is
/// handed out by the window server and means nothing after a reboot, so restoring
/// last week's assignments would scatter today's windows at random. The layout
/// settings are persisted, because those are a preference rather than a snapshot.
nonisolated struct TilingWorkspace: Identifiable, Sendable {
    let index: Int
    var mode: LayoutMode = .dwindle
    /// Split positions by depth. Empty means every split is even.
    var ratios: [CGFloat] = []
    var mainCount: Int = 1
    /// Window order, which is what the layout reads. Position in this array is the
    /// window's position on screen, so swapping two entries swaps two panes.
    var order: [CGWindowID] = []
    /// Windows the user pulled out of the tiling, which keep whatever size and
    /// position they had.
    var floating: Set<CGWindowID> = []
    /// The one window temporarily filling the screen, if any.
    var zoomed: CGWindowID?

    var id: Int { index }
}

/// The window manager.
///
/// Owns which windows exist, which workspace each belongs to, and where they are
/// put. Everything that changes the desktop goes through `apply()`, so there is
/// exactly one place that writes a window frame and one order of operations to
/// reason about when something ends up in the wrong place.
@MainActor
@Observable
final class TilingEngine {
    static let shared = TilingEngine()

    static let workspaceCount = 9

    /// Written by the command layer in `TilingCommands.swift`, which is why these
    /// three are not `private(set)` like the rest — that access level is per-file,
    /// and Swift has no way to say "writable within the module" more narrowly.
    var workspaces: [TilingWorkspace]
    var activeWorkspace: Int = 1
    /// Set when something could not be done, for the panel to show. Cleared on the
    /// next successful command rather than on a timer, so it survives long enough
    /// to be read.
    var status: String?

    /// Every managed window, by id, as of the last refresh.
    private(set) var windows: [CGWindowID: TilingWindow] = [:]
    private(set) var isRunning = false

    private var observer: TilingObserver?
    private var refreshTask: Task<Void, Never>?
    /// Guards against reacting to our own window writes as if they were the user's.
    private var isApplying = false
    /// The display a window belongs to, remembered while it is parked off-screen
    /// where its own frame no longer says which monitor it came from.
    private var homeDisplay: [CGWindowID: CGDirectDisplayID] = [:]

    /// Windows that refused to shrink to the slot they were given, and so are
    /// being left alone. Not persisted and not a user setting: it is a fact about
    /// the window that was discovered by trying, and it is cleared on an explicit
    /// re-tile so a window that has since become resizable gets another chance.
    private(set) var rigid: Set<CGWindowID> = []

    private init() {
        workspaces = (1 ... Self.workspaceCount).map { index in
            var workspace = TilingWorkspace(index: index)
            workspace.mode = Preferences.tilingLayout(forWorkspace: index)
            return workspace
        }
    }

    // MARK: - Lifecycle

    /// Starts managing windows. Safe to call when already running.
    func start() {
        guard !isRunning else { return }
        guard AX.isTrusted else {
            status = "Crest needs Accessibility permission to move windows."
            AX.requestTrust()
            return
        }

        isRunning = true
        status = nil
        observer = TilingObserver { [weak self] in self?.scheduleRefresh() }
        observer?.start()
        refresh()
    }

    /// Stops managing windows and gives every parked window back.
    ///
    /// Unparking is not optional. A window left off the right edge of the desktop
    /// when the tiler stops is a window the user cannot reach with the mouse and
    /// has no way to recover except by knowing to turn tiling back on.
    func stop() {
        guard isRunning else { return }
        refreshTask?.cancel()
        observer?.stop()
        observer = nil
        isRunning = false

        for window in windows.values where Display.isParked(window.frame ?? .zero) {
            restore(window)
        }
        status = nil
    }

    func toggle() {
        isRunning ? stop() : start()
        Preferences.tilingEnabled = isRunning
    }

    // MARK: - Refresh

    /// Coalesces a burst of Accessibility events into one layout pass.
    ///
    /// Opening a window produces several notifications in a few milliseconds —
    /// created, then focused, then the app activating. Laying out on each of them
    /// makes the new window visibly jump between two or three positions before it
    /// settles.
    private func scheduleRefresh() {
        guard isRunning, !isApplying else { return }
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(90))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    /// Re-reads the window list and lays it out.
    func refresh() {
        guard isRunning else { return }
        rigid = []

        let found = WindowEnumerator.current(extraExcludedBundleIDs: Preferences.tilingExcludedBundleIDs)
        windows = Dictionary(uniqueKeysWithValues: found.map { ($0.id, $0) })
        let live = Set(windows.keys)

        for index in workspaces.indices {
            workspaces[index].order.removeAll { !live.contains($0) }
            workspaces[index].floating.formIntersection(live)
            if let zoomed = workspaces[index].zoomed, !live.contains(zoomed) {
                workspaces[index].zoomed = nil
            }
        }

        // A window nothing has claimed is new, and new windows join the workspace
        // the user is looking at — which is the only one where a window appearing
        // is not a surprise.
        let claimed = Set(workspaces.flatMap(\.order))
        for id in found.map(\.id) where !claimed.contains(id) {
            workspaces[activeWorkspace - 1].order.append(id)
        }

        apply()
    }

    // MARK: - Applying the layout

    /// Writes every window frame for the current state. The only place that does.
    func apply() {
        guard isRunning, AX.isTrusted else { return }
        isApplying = true
        defer { isApplying = false }

        let active = workspaces[activeWorkspace - 1]

        // Everything not in the visible workspace goes off-screen first, so the
        // space it occupied is free before the visible windows are placed into it.
        let visible = Set(active.order)
        for (id, window) in windows where !visible.contains(id) {
            park(window)
        }

        for id in active.floating {
            guard let window = windows[id] else { continue }
            restore(window)
        }

        if let zoomed = active.zoomed, let window = windows[zoomed] {
            restore(window)
            let screen = displayFrame(for: window)
            let inset = CGFloat(Preferences.tilingOuterGap)
            AX.setFrame(screen.insetBy(dx: inset, dy: inset), of: window.element)
            return
        }

        let tiled = active.order.filter { !active.floating.contains($0) }
        guard !tiled.isEmpty else { return }

        // Each display is tiled independently, so a window dragged to the second
        // monitor stays there and shares that screen with its neighbours rather
        // than being folded back into the first screen's layout.
        let byDisplay = Dictionary(grouping: tiled) { id -> CGDirectDisplayID in
            guard let window = windows[id] else { return mainDisplayID }
            return displayID(for: window)
        }

        for (display, ids) in byDisplay {
            guard let area = usableFrame(of: display) else { continue }
            let tileable = ids.filter { !rigid.contains($0) }
            place(tileable, in: area, workspace: active)
        }
    }

    /// Lays windows out in an area and makes sure they actually went where they
    /// were put.
    ///
    /// The layout arithmetic cannot overlap — that is checked directly in
    /// `Tests/tiling.sh` — but the windows still can, because a window is not
    /// obliged to accept the size it is given. Almost every app has a minimum, and
    /// one whose minimum is wider than its slot simply stays wider, sitting on top
    /// of its neighbour. Nothing reports this: the write succeeds and the frame
    /// comes back wrong.
    ///
    /// So the frames are read back after writing. Most windows that miss on the
    /// first attempt settle on a second, because a window being moved and resized
    /// in the same pass can clamp against its old bounds. What still overflows
    /// after that has a hard minimum, and no amount of asking will change it.
    private func place(_ ids: [CGWindowID], in area: CGRect, workspace: TilingWorkspace) {
        guard !ids.isEmpty else { return }

        let frames = TilingLayout.frames(
            count: ids.count,
            in: area,
            mode: workspace.mode,
            gap: CGFloat(Preferences.tilingInnerGap),
            outerGap: CGFloat(Preferences.tilingOuterGap),
            ratios: workspace.ratios,
            mainCount: workspace.mainCount
        )

        var stubborn: [(CGWindowID, CGRect)] = []
        for (id, frame) in zip(ids, frames) {
            guard let window = windows[id] else { continue }
            AX.setFrame(frame, of: window.element)
            if overflows(window, given: frame) { stubborn.append((id, frame)) }
        }

        guard !stubborn.isEmpty else { return }

        var refused: Set<CGWindowID> = []
        for (id, frame) in stubborn {
            guard let window = windows[id] else { continue }
            AX.setFrame(frame, of: window.element)
            if overflows(window, given: frame) { refused.insert(id) }
        }

        guard !refused.isEmpty else { return }

        // Taking them out of the tiling and laying out the rest is the only way to
        // get a clean layout from here. Left in, a window that cannot shrink keeps
        // its slot *and* covers its neighbour, so two windows are wrong instead of
        // one. Floated, it is one oversized window over a layout that is otherwise
        // correct, and the status line says which app did it.
        rigid.formUnion(refused)
        let names = refused.compactMap { windows[$0]?.appName }
        status = names.isEmpty
            ? nil
            : "\(ListFormatter.localizedString(byJoining: Array(Set(names)))) won't tile that small, so it's floating"

        place(ids.filter { !refused.contains($0) }, in: area, workspace: workspace)
    }

    /// Whether a window came to rest larger than the frame it was handed.
    ///
    /// Two points of slack, because a window whose height is odd cannot land on an
    /// integral frame exactly and reporting that as a refusal would float half the
    /// desktop.
    private func overflows(_ window: TilingWindow, given frame: CGRect) -> Bool {
        guard let actual = window.frame else { return false }
        return actual.width > frame.width + 2 || actual.height > frame.height + 2
    }

    private func park(_ window: TilingWindow) {
        guard let frame = window.frame, !Display.isParked(frame) else { return }
        homeDisplay[window.id] = displayID(for: window)
        AX.setFrame(Display.parkingSpot(for: frame.size), of: window.element)
    }

    /// Brings a parked window back onto its screen, leaving its size alone.
    private func restore(_ window: TilingWindow) {
        guard let frame = window.frame, Display.isParked(frame) else { return }
        let area = usableFrame(of: homeDisplay[window.id] ?? mainDisplayID) ?? .zero
        let size = CGSize(width: min(frame.width, area.width), height: min(frame.height, area.height))
        let origin = CGPoint(
            x: area.midX - size.width / 2,
            y: area.midY - size.height / 2
        )
        AX.setFrame(CGRect(origin: origin, size: size), of: window.element)
    }

    // MARK: - Displays

    private var mainDisplayID: CGDirectDisplayID {
        displayID(of: NSScreen.main ?? NSScreen.screens.first) ?? CGMainDisplayID()
    }

    private func displayID(for window: TilingWindow) -> CGDirectDisplayID {
        guard let frame = window.frame, !Display.isParked(frame) else {
            return homeDisplay[window.id] ?? mainDisplayID
        }
        return displayID(of: Display.screen(containing: frame)) ?? mainDisplayID
    }

    private func displayID(of screen: NSScreen?) -> CGDirectDisplayID? {
        screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    private func screen(for display: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { displayID(of: $0) == display }
    }

    private func usableFrame(of display: CGDirectDisplayID) -> CGRect? {
        screen(for: display).map(Display.usableFrame(of:))
    }

    private func displayFrame(for window: TilingWindow) -> CGRect {
        usableFrame(of: displayID(for: window)) ?? .zero
    }
}
