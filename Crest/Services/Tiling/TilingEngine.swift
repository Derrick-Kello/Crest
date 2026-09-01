//
//  TilingEngine.swift
//  Crest
//

import AppKit
import ApplicationServices
import Observation
import QuartzCore

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
    /// The last managed window that had keyboard focus.
    ///
    /// Needed because a command run from the command bar arrives with Crest itself
    /// in front: the bar has to take focus to be typed into, so by the time the
    /// command runs, the focused window is Crest's own panel and no tiling command
    /// has anything to act on. Remembering the window the user came from is what
    /// lets "Send Window to Workspace 3" mean the window they were just in.
    var lastFocused: CGWindowID?
    /// Set when something could not be done, for the panel to show. Cleared on the
    /// next successful command rather than on a timer, so it survives long enough
    /// to be read.
    var status: String?

    /// Every managed window, by id, as of the last refresh.
    private(set) var windows: [CGWindowID: TilingWindow] = [:]
    private(set) var isRunning = false

    private var observer: TilingObserver?
    private var refreshTask: Task<Void, Never>?
    /// The display a window belongs to, remembered while it is parked off-screen
    /// where its own frame no longer says which monitor it came from.
    private var homeDisplay: [CGWindowID: CGDirectDisplayID] = [:]

    /// Windows that refused to shrink to the slot they were given, and so are
    /// being left alone. Not persisted and not a user setting: it is a fact about
    /// the window that was discovered by trying, and it is cleared on an explicit
    /// re-tile so a window that has since become resizable gets another chance.
    private(set) var rigid: Set<CGWindowID> = []

    /// The smallest size each app has been seen to accept, keyed by bundle id.
    ///
    /// Learned by watching, because there is no way to ask. `kAXMinValue` is not
    /// implemented for windows, and an app's real minimum lives in its own layout
    /// code — so the only way to find out that Xcode will not go below about six
    /// hundred points is to give it less and read back what it did instead. Kept
    /// per app rather than per window because the constraint belongs to the app,
    /// which means the fourth window of a session inherits what the first taught
    /// us rather than having to overlap something once to be measured.
    private var learnedMinimums: [String: CGSize] = [:]

    /// Suppresses the refresh that Crest's own writes provoke.
    ///
    /// Moving a window makes the owning app post `moved` and `resized`
    /// notifications, which arrive back here looking exactly like the user
    /// dragging something. Answering them relays out the desktop, which moves the
    /// windows, which posts more notifications. A plain boolean was enough while
    /// every frame was written synchronously inside `apply()`; now that a move
    /// takes a fifth of a second, the guard has to last as long as the movement
    /// does, plus a beat for the notifications trailing behind it.
    private var quietUntil: CFTimeInterval = 0
    private var isApplying: Bool { CACurrentMediaTime() < quietUntil }

    /// How many times in a row a layout pass has ended in another layout pass
    /// because a window would not fit. Bounded so that an app whose minimum size
    /// changes as fast as we can measure it cannot spin the engine.
    private var consecutiveCorrections = 0

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
        TilingAnimator.shared.stop()
        observer?.stop()
        observer = nil
        isRunning = false

        for window in windows.values {
            guard let frame = restoredFrame(for: window) else { continue }
            AX.setFrame(frame, of: window.element)
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
            guard let self, !self.isApplying else { return }
            self.refresh()
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

        if let focused = WindowEnumerator.focused(), live.contains(focused) {
            lastFocused = focused
        }
        if let remembered = lastFocused, !live.contains(remembered) {
            lastFocused = nil
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

    /// The re-tile the user asked for: forgets everything the engine has worked
    /// out by trial and starts again.
    ///
    /// Separate from `refresh()` because that one runs on every Accessibility
    /// event. Throwing away the measured minimums there would mean re-learning
    /// them — by letting a window overlap its neighbour once — every time anybody
    /// clicked anything.
    func retile() {
        learnedMinimums = [:]
        consecutiveCorrections = 0
        refresh()
        status = "Windows re-tiled"
    }

    // MARK: - Applying the layout

    /// Works out where every window belongs and moves it there. The only place
    /// that does.
    func apply(animated: Bool = true) {
        guard isRunning, AX.isTrusted else { return }

        let active = workspaces[activeWorkspace - 1]

        // Parking and unparking are never animated. Parking is meant to be
        // invisible — sliding a window off the edge of the desktop over a fifth of
        // a second is the one thing that would make it visible — and a window
        // coming back has nowhere to come back *from* that the user has seen.
        let visible = Set(active.order)
        for (id, window) in windows where !visible.contains(id) {
            guard let frame = parkedFrame(for: window) else { continue }
            homeDisplay[id] = displayID(for: window)
            AX.setFrame(frame, of: window.element)
        }
        for id in active.floating {
            guard let window = windows[id], let frame = restoredFrame(for: window) else { continue }
            AX.setFrame(frame, of: window.element)
        }

        var moves: [(window: TilingWindow, frame: CGRect)] = []

        if let zoomed = active.zoomed, let window = windows[zoomed] {
            if let frame = restoredFrame(for: window) { AX.setFrame(frame, of: window.element) }
            let inset = CGFloat(Preferences.tilingOuterGap)
            moves = [(window, displayFrame(for: window).insetBy(dx: inset, dy: inset))]
        } else {
            moves = tiledMoves(in: active)
        }

        run(moves, animated: animated)
    }

    /// Every tiled window's destination, laid out per display.
    ///
    /// Each display is tiled independently, so a window dragged to the second
    /// monitor stays there and shares that screen with its neighbours rather than
    /// being folded back into the first screen's layout.
    private func tiledMoves(in workspace: TilingWorkspace) -> [(window: TilingWindow, frame: CGRect)] {
        let tiled = workspace.order.filter { !workspace.floating.contains($0) && !rigid.contains($0) }
        guard !tiled.isEmpty else { return [] }

        let byDisplay = Dictionary(grouping: tiled) { id -> CGDirectDisplayID in
            guard let window = windows[id] else { return mainDisplayID }
            return displayID(for: window)
        }

        var moves: [(window: TilingWindow, frame: CGRect)] = []
        for (display, ids) in byDisplay {
            guard let area = usableFrame(of: display) else { continue }

            let frames = TilingLayout.frames(
                count: ids.count,
                in: area,
                mode: workspace.mode,
                gap: CGFloat(Preferences.tilingInnerGap),
                outerGap: CGFloat(Preferences.tilingOuterGap),
                ratios: workspace.ratios,
                mainCount: workspace.mainCount,
                minimums: ids.map { minimum(for: $0) }
            )

            for (id, frame) in zip(ids, frames) {
                guard let window = windows[id] else { continue }
                moves.append((window, frame))
            }
        }
        return moves
    }

    /// Hands the moves to the animator and holds off reacting to them.
    private func run(_ moves: [(window: TilingWindow, frame: CGRect)], animated: Bool) {
        let settle = TilingAnimator.duration(forCount: moves.count) + 0.25
        quietUntil = max(quietUntil, CACurrentMediaTime() + settle)

        TilingAnimator.shared.move(moves, animated: animated && Preferences.tilingAnimations) { [weak self] in
            self?.reconcile(moves)
        }
    }

    // MARK: - Checking the layout landed

    /// Reads back where the windows actually went, and reacts to the ones that
    /// went somewhere else.
    ///
    /// The layout arithmetic cannot overlap — that is checked directly in
    /// `Tests/tiling.sh` — but the windows still can, because a window is not
    /// obliged to accept the size it is given. Almost every app has a minimum, and
    /// one whose minimum is wider than its slot simply stays wider, sitting on top
    /// of its neighbour. Nothing reports this: the write succeeds and the frame
    /// comes back wrong.
    ///
    /// So the size a window settled at is recorded as what that app actually needs
    /// and the layout is asked again, this time with that width reserved. The
    /// neighbour ends up narrower, which is a layout the user can work in, instead
    /// of hidden, which is not. Only if the app cannot be accommodated even then —
    /// its minimum is a large fraction of the screen — is it dropped out of the
    /// tiling altogether.
    private func reconcile(_ moves: [(window: TilingWindow, frame: CGRect)]) {
        guard isRunning else { return }

        var learnedSomething = false
        var refused: Set<CGWindowID> = []

        for (window, frame) in moves {
            guard let actual = window.frame, overflows(actual, given: frame) else { continue }

            let key = minimumKey(for: window)
            let known = learnedMinimums[key] ?? .zero

            // Only the axis that actually overflowed is learned from. A window
            // that refused to narrow but accepted its height came back exactly as
            // tall as the slot it was given, and recording *that* as a minimum
            // would reserve a slot-sized height for the app from then on — a
            // number that has nothing to do with the window and everything to do
            // with how many windows happened to be open when it was measured.
            let measured = CGSize(
                width: actual.width > frame.width + 2 ? max(known.width, actual.width) : known.width,
                height: actual.height > frame.height + 2 ? max(known.height, actual.height) : known.height
            )

            if measured.width > known.width + 1 || measured.height > known.height + 1 {
                learnedMinimums[key] = measured
                learnedSomething = true
            } else {
                // Already knew, reserved the space, and the window still spilled
                // out of it. Nothing more to learn and nothing more to try.
                refused.insert(window.id)
            }
        }

        guard learnedSomething || !refused.isEmpty else {
            consecutiveCorrections = 0
            return
        }

        // Taking a window out of the tiling is the last resort. Left in, one that
        // cannot shrink keeps its slot *and* covers its neighbour, so two windows
        // are wrong instead of one. Out, it is one oversized window over a layout
        // that is otherwise correct, and the status line says which app did it.
        if !refused.isEmpty {
            rigid.formUnion(refused)
            let names = refused.compactMap { windows[$0]?.appName }
            if !names.isEmpty {
                status = "\(ListFormatter.localizedString(byJoining: Array(Set(names)))) won't tile that small, so it's floating"
            }
        }

        consecutiveCorrections += 1
        guard consecutiveCorrections <= 3 else { return }

        // Not animated: this is a correction, and sliding the whole desktop a
        // second time turns one clean movement into a wobble.
        apply(animated: false)
    }

    /// Whether a window came to rest larger than the frame it was handed.
    ///
    /// Two points of slack, because a window whose height is odd cannot land on an
    /// integral frame exactly and reporting that as a refusal would float half the
    /// desktop.
    private func overflows(_ actual: CGRect, given frame: CGRect) -> Bool {
        actual.width > frame.width + 2 || actual.height > frame.height + 2
    }

    /// The smallest size the app owning this window is known to accept.
    private func minimum(for id: CGWindowID) -> CGSize {
        guard let window = windows[id] else { return .zero }
        return learnedMinimums[minimumKey(for: window)] ?? .zero
    }

    /// Bundle id where there is one, app name otherwise — the point is that two
    /// windows of the same app share what has been learned about either.
    private func minimumKey(for window: TilingWindow) -> String {
        window.bundleID ?? window.appName
    }

    // MARK: - Parking

    /// Where a window goes to be out of the way, or nil when it is already there.
    private func parkedFrame(for window: TilingWindow) -> CGRect? {
        guard let frame = window.frame, !Display.isParked(frame) else { return nil }
        return Display.parkingSpot(for: frame.size)
    }

    /// Where a parked window comes back to, leaving its size alone, or nil when it
    /// was never parked.
    private func restoredFrame(for window: TilingWindow) -> CGRect? {
        guard let frame = window.frame, Display.isParked(frame) else { return nil }
        let area = usableFrame(of: homeDisplay[window.id] ?? mainDisplayID) ?? .zero
        let size = CGSize(width: min(frame.width, area.width), height: min(frame.height, area.height))
        return CGRect(
            origin: CGPoint(x: area.midX - size.width / 2, y: area.midY - size.height / 2),
            size: size
        )
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
