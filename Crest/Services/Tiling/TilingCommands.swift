//
//  TilingCommands.swift
//  Crest
//

import AppKit
import CoreGraphics

/// A direction on screen, as pressed.
nonisolated enum TilingDirection: String, CaseIterable, Sendable {
    case left, down, up, right

    /// Accessibility's y axis grows downward, so "up" is toward zero. Getting this
    /// backwards is invisible in the arithmetic and obvious the moment you press a
    /// key, which is a bad combination — hence one named place for the sign.
    var vector: CGVector {
        switch self {
        case .left: CGVector(dx: -1, dy: 0)
        case .right: CGVector(dx: 1, dy: 0)
        case .up: CGVector(dx: 0, dy: -1)
        case .down: CGVector(dx: 0, dy: 1)
        }
    }

    var isHorizontal: Bool { self == .left || self == .right }
}

extension TilingEngine {

    // MARK: - Focus

    /// Moves keyboard focus to the nearest window in a direction.
    ///
    /// Geometric rather than positional: it asks which window is actually over
    /// there on the glass, not which one is next in the layout array. With a
    /// dwindle layout those are different answers often enough to matter — the
    /// window to the right of the third pane is not the fourth one.
    func focus(_ direction: TilingDirection) {
        guard let current = focusedWindow(), let origin = current.frame else { return }
        guard let target = nearest(to: origin, in: direction, among: visibleWindows()) else { return }
        target.focus()
        status = nil
    }

    /// Focus the next or previous window in layout order, wrapping around. The
    /// fallback for when nothing lies in the direction you pressed.
    func focusCycling(forward: Bool) {
        let order = workspaces[activeWorkspace - 1].order
        guard !order.isEmpty else { return }

        let current = focusedWindow().flatMap { order.firstIndex(of: $0.id) } ?? 0
        let next = (current + (forward ? 1 : -1) + order.count) % order.count
        windows[order[next]]?.focus()
    }

    // MARK: - Rearranging

    /// Swaps the focused window with its neighbour in a direction.
    func swap(_ direction: TilingDirection) {
        guard let current = focusedWindow(), let origin = current.frame else { return }
        guard let target = nearest(to: origin, in: direction, among: visibleWindows()) else { return }

        var order = workspaces[activeWorkspace - 1].order
        guard let from = order.firstIndex(of: current.id),
              let to = order.firstIndex(of: target.id)
        else { return }

        order.swapAt(from, to)
        workspaces[activeWorkspace - 1].order = order
        apply()
        // Focus follows the window, not the slot — otherwise every swap also
        // silently moves you to a different window.
        current.focus()
    }

    /// Promotes the focused window to the first slot, which in `tall` and `wide` is
    /// the main pane and in `dwindle` is the largest.
    func promoteFocused() {
        guard let current = focusedWindow() else { return }
        var order = workspaces[activeWorkspace - 1].order
        guard let index = order.firstIndex(of: current.id), index != 0 else { return }

        order.remove(at: index)
        order.insert(current.id, at: 0)
        workspaces[activeWorkspace - 1].order = order
        apply()
        current.focus()
    }

    // MARK: - Workspaces

    func switchTo(workspace index: Int) {
        guard (1 ... Self.workspaceCount).contains(index), index != activeWorkspace else { return }
        activeWorkspace = index
        apply()

        // Focus has to be handed somewhere explicitly. The windows that were on
        // screen a moment ago have just been parked off it, and macOS leaves focus
        // on the parked one, so the keyboard would still be typing into a window
        // the user can no longer see.
        if let first = workspaces[index - 1].order.first, let window = windows[first] {
            window.focus()
        } else {
            NSApp.activate()
        }
        status = "Workspace \(index)"
    }

    func switchToWorkspaceCycling(forward: Bool) {
        let next = (activeWorkspace - 1 + (forward ? 1 : -1) + Self.workspaceCount) % Self.workspaceCount
        switchTo(workspace: next + 1)
    }

    /// Sends the focused window to another workspace and stays where you are.
    func moveFocused(toWorkspace index: Int) {
        guard (1 ... Self.workspaceCount).contains(index), index != activeWorkspace else { return }
        guard let current = focusedWindow() else { return }

        workspaces[activeWorkspace - 1].order.removeAll { $0 == current.id }
        workspaces[activeWorkspace - 1].floating.remove(current.id)
        if workspaces[activeWorkspace - 1].zoomed == current.id {
            workspaces[activeWorkspace - 1].zoomed = nil
        }
        workspaces[index - 1].order.append(current.id)

        apply()
        status = "Sent \(current.appName) to workspace \(index)"
    }

    /// Sends the focused window to another workspace and follows it there.
    func followFocused(toWorkspace index: Int) {
        moveFocused(toWorkspace: index)
        switchTo(workspace: index)
    }

    // MARK: - Layout

    func setLayout(_ mode: LayoutMode) {
        workspaces[activeWorkspace - 1].mode = mode
        // Ratios are per-split and mean something different in each layout, so
        // carrying them across a change leaves the new layout lopsided for no
        // reason the user could connect to what they pressed.
        workspaces[activeWorkspace - 1].ratios = []
        Preferences.setTilingLayout(mode, forWorkspace: activeWorkspace)
        apply()
        status = mode.title
    }

    func cycleLayout() {
        setLayout(workspaces[activeWorkspace - 1].mode.next)
    }

    /// Grows or shrinks the split the focused window sits on.
    ///
    /// For `dwindle` the split that matters is the one at the window's own depth,
    /// so resizing the third pane does not move the first one. For the main-and-
    /// stack layouts there is only one split worth dragging.
    func resize(by delta: CGFloat) {
        let workspace = workspaces[activeWorkspace - 1]
        let depth: Int = switch workspace.mode {
        case .dwindle:
            focusedWindow().flatMap { workspace.order.firstIndex(of: $0.id) }.map { max(0, $0 - 1) } ?? 0
        case .tall, .wide, .monocle:
            0
        }

        var ratios = workspace.ratios
        while ratios.count <= depth { ratios.append(0.5) }
        ratios[depth] = min(max(ratios[depth] + delta, 0.1), 0.9)

        workspaces[activeWorkspace - 1].ratios = ratios
        apply()
    }

    func adjustMainCount(by delta: Int) {
        let count = workspaces[activeWorkspace - 1].order.count
        let updated = workspaces[activeWorkspace - 1].mainCount + delta
        workspaces[activeWorkspace - 1].mainCount = min(max(updated, 1), max(1, count - 1))
        apply()
    }

    /// Resets the splits of the current workspace to even.
    func balance() {
        workspaces[activeWorkspace - 1].ratios = []
        workspaces[activeWorkspace - 1].mainCount = 1
        apply()
        status = "Balanced"
    }

    // MARK: - Per-window state

    /// Pulls the focused window out of the tiling, or puts it back.
    func toggleFloat() {
        guard let current = focusedWindow() else { return }
        var floating = workspaces[activeWorkspace - 1].floating

        if floating.contains(current.id) {
            floating.remove(current.id)
            status = "Tiled \(current.appName)"
        } else {
            floating.insert(current.id)
            status = "Floating \(current.appName)"
        }

        workspaces[activeWorkspace - 1].floating = floating
        apply()
        current.focus()
    }

    /// Fills the screen with the focused window, or gives the layout back.
    ///
    /// Not the green-button fullscreen: that moves the window into a Space of its
    /// own, which the tiler cannot follow it into. This just makes it as large as
    /// the screen allows and leaves it where the tiler can still reach it.
    func toggleZoom() {
        guard let current = focusedWindow() else { return }
        let workspace = workspaces[activeWorkspace - 1]
        workspaces[activeWorkspace - 1].zoomed = workspace.zoomed == current.id ? nil : current.id
        apply()
        current.focus()
    }

    func closeFocused() {
        guard let current = focusedWindow() else { return }
        current.close()
        // The destroyed notification arrives on its own, but a beat later; asking
        // now keeps the gap from being visible.
        scheduleImmediateRefresh()
    }

    // MARK: - Lookups

    /// The focused window, if the tiler manages it.
    func focusedWindow() -> TilingWindow? {
        guard let id = WindowEnumerator.focused(), let window = windows[id] else { return nil }
        return workspaces[activeWorkspace - 1].order.contains(id) ? window : nil
    }

    private func visibleWindows() -> [TilingWindow] {
        workspaces[activeWorkspace - 1].order.compactMap { windows[$0] }
    }

    /// The closest window lying in `direction` from `origin`.
    ///
    /// Candidates are filtered by the dominant axis of their offset rather than by
    /// a strict half-plane: a window up and slightly to the left of you is "up",
    /// and requiring a pure vertical offset would make it unreachable. Distance is
    /// measured between centres, with the off-axis component weighted so that a
    /// window far to the side does not win over one directly ahead.
    private func nearest(to origin: CGRect, in direction: TilingDirection, among candidates: [TilingWindow]) -> TilingWindow? {
        let from = CGPoint(x: origin.midX, y: origin.midY)

        return candidates
            .compactMap { window -> (TilingWindow, CGFloat)? in
                guard let frame = window.frame, frame != origin else { return nil }
                let to = CGPoint(x: frame.midX, y: frame.midY)
                let dx = to.x - from.x
                let dy = to.y - from.y

                let along = direction.isHorizontal ? dx : dy
                let across = direction.isHorizontal ? dy : dx
                let sign: CGFloat = direction.isHorizontal ? direction.vector.dx : direction.vector.dy

                // Must lie in the pressed direction, and must be more in that
                // direction than off to the side of it.
                guard along * sign > 1, abs(along) >= abs(across) else { return nil }
                return (window, abs(along) + abs(across) * 2)
            }
            .min { $0.1 < $1.1 }?.0
    }

    private func scheduleImmediateRefresh() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            self?.refresh()
        }
    }
}
