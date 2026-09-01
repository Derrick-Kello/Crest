//
//  TilingLayout.swift
//  Crest
//

import CoreGraphics
import Foundation

/// How a workspace arranges its windows.
nonisolated enum LayoutMode: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Hyprland's default, and Omarchy's: every new window halves the space of the
    /// one before it, alternating between a vertical and a horizontal cut. Two
    /// windows are side by side, three make an L, four make a spiral.
    case dwindle
    /// One large pane on the left, everything else stacked down the right. The
    /// layout to reach for when one window is the work and the rest are reference.
    case tall
    /// `tall` rotated: the main pane spans the top. Suited to wide monitors.
    case wide
    /// One window at a time, filling the screen, the others behind it.
    case monocle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dwindle: "Dwindle"
        case .tall: "Tall"
        case .wide: "Wide"
        case .monocle: "Monocle"
        }
    }

    var symbolName: String {
        switch self {
        case .dwindle: "square.split.bottomrightquarter"
        case .tall: "rectangle.split.2x1"
        case .wide: "rectangle.split.1x2"
        case .monocle: "square"
        }
    }

    var next: LayoutMode {
        let all = LayoutMode.allCases
        let index = all.firstIndex(of: self) ?? 0
        return all[(index + 1) % all.count]
    }
}

/// Turns a window count into a set of rectangles.
///
/// Deliberately pure: no window handles, no Accessibility, no state. The engine
/// decides *which* windows are in a workspace and this decides *where* they go,
/// which is what makes the arithmetic testable without a Mac full of open apps.
nonisolated enum TilingLayout {

    /// Frames for `count` windows, in order, inside `area`.
    ///
    /// - Parameters:
    ///   - ratios: Split positions, indexed by depth for `dwindle` and by nothing
    ///     in particular for the others, which use only the first. A missing entry
    ///     means an even split, so an empty array is a valid input and gives the
    ///     default layout.
    ///   - mainCount: How many windows share the main pane in `tall` and `wide`.
    ///   - minimums: The smallest each window is known to accept, in the same
    ///     order. Empty, or a zero entry, means nothing is known about that window
    ///     and it gets whatever an even split gives it.
    static func frames(
        count: Int,
        in area: CGRect,
        mode: LayoutMode,
        gap: CGFloat,
        outerGap: CGFloat,
        ratios: [CGFloat] = [],
        mainCount: Int = 1,
        minimums: [CGSize] = []
    ) -> [CGRect] {
        guard count > 0 else { return [] }

        // Insetting the container by the outer gap less half the inner gap means
        // that after every frame is inset by half the inner gap below, the space
        // between two windows is exactly `gap` and the space to the screen edge is
        // exactly `outerGap`. Doing it in one step at the end would make the edges
        // and the seams disagree by a factor of two.
        let container = area.insetBy(dx: outerGap - gap / 2, dy: outerGap - gap / 2)
        guard container.width > 0, container.height > 0 else { return [] }

        let demands = demanded(count: count, minimums: minimums, gap: gap, within: container)

        let raw: [CGRect] = switch mode {
        case .dwindle: dwindle(demands[...], in: container, ratios: ratios, depth: 0)
        case .tall: mainStack(demands, in: container, ratio: ratios.first ?? 0.5, mainCount: mainCount, vertical: true)
        case .wide: mainStack(demands, in: container, ratio: ratios.first ?? 0.5, mainCount: mainCount, vertical: false)
        case .monocle: Array(repeating: container, count: count)
        }

        return raw.map { snapped(inset($0, by: gap / 2)) }
    }

    /// The space each window needs *including* its share of the gaps, clamped so
    /// that one app with an absurd minimum cannot ask for more than the screen.
    ///
    /// A window's minimum is a fact about the window, but the layout works in
    /// slots, and a slot is the window plus a half-gap on every side. Adding the
    /// gap here is what keeps the two units from being confused downstream.
    private static func demanded(count: Int, minimums: [CGSize], gap: CGFloat, within container: CGRect) -> [CGSize] {
        (0 ..< count).map { index in
            let minimum = minimums.indices.contains(index) ? minimums[index] : .zero
            guard minimum.width > 0 || minimum.height > 0 else { return .zero }
            return CGSize(
                width: min(minimum.width + gap, container.width),
                height: min(minimum.height + gap, container.height)
            )
        }
    }

    // MARK: - Dwindle

    /// The recursive spiral. The last window takes whatever is left, which is what
    /// keeps the layout gapless however the ratios were dragged.
    private static func dwindle(_ demands: ArraySlice<CGSize>, in rect: CGRect, ratios: [CGFloat], depth: Int) -> [CGRect] {
        guard let mine = demands.first, demands.count > 1 else { return [rect] }

        // Split across the longer axis, so panes tend back towards square instead
        // of degenerating into slivers as the count climbs.
        let vertical = rect.width >= rect.height
        let extent = vertical ? rect.width : rect.height
        let theirs = demands.dropFirst().map { vertical ? $0.width : $0.height }.max() ?? 0

        let wanted = ratios.indices.contains(depth) ? ratios[depth] : 0.5
        let allowed = bounds(mine: vertical ? mine.width : mine.height, theirs: theirs, extent: extent)
        let cut = min(max(wanted, allowed.lowerBound), allowed.upperBound)

        let (first, rest) = rect.split(atFraction: cut, vertical: vertical)
        return [first] + dwindle(demands.dropFirst(), in: rest, ratios: ratios, depth: depth + 1)
    }

    // MARK: - Main and stack

    private static func mainStack(_ demands: [CGSize], in rect: CGRect, ratio: CGFloat, mainCount: Int, vertical: Bool) -> [CGRect] {
        let count = demands.count
        let mains = max(1, min(mainCount, count))

        // Along the main/stack cut it is the *widest* demand in a group that
        // decides how much that group needs; across it, every window in the group
        // gets its own share, so the two axes are asked for separately.
        let across: (CGSize) -> CGFloat = { vertical ? $0.height : $0.width }
        let along: (CGSize) -> CGFloat = { vertical ? $0.width : $0.height }

        guard count > mains else {
            return divide(rect, demands: demands.map(across), vertical: !vertical)
        }

        let main = Array(demands.prefix(mains))
        let stack = Array(demands.dropFirst(mains))
        let allowed = bounds(
            mine: main.map(along).max() ?? 0,
            theirs: stack.map(along).max() ?? 0,
            extent: vertical ? rect.width : rect.height
        )
        let cut = min(max(ratio, allowed.lowerBound), allowed.upperBound)

        let (mainArea, stackArea) = rect.split(atFraction: cut, vertical: vertical)
        return divide(mainArea, demands: main.map(across), vertical: !vertical)
            + divide(stackArea, demands: stack.map(across), vertical: !vertical)
    }

    /// Cuts a rectangle into one part per demand. `vertical` splits left-to-right.
    private static func divide(_ rect: CGRect, demands: [CGFloat], vertical: Bool) -> [CGRect] {
        guard !demands.isEmpty else { return [] }

        let extents = share(vertical ? rect.width : rect.height, among: demands)
        var offset = vertical ? rect.minX : rect.minY

        return extents.map { extent in
            defer { offset += extent }
            return vertical
                ? CGRect(x: offset, y: rect.minY, width: extent, height: rect.height)
                : CGRect(x: rect.minX, y: offset, width: rect.width, height: extent)
        }
    }

    // MARK: - Sharing a length out

    /// Splits `total` into one part per demand: an equal share each, except that
    /// anything asking for more than its share takes what it needs and the rest
    /// divide what is left.
    ///
    /// This is the arithmetic that stops the fourth window overlapping the third.
    /// An even split assumes every window will accept whatever width it is handed,
    /// and most will — but an app with a 600-point minimum handed a 480-point slot
    /// simply stays 600 wide and covers its neighbour. Reserving the width it is
    /// going to take anyway means the neighbour is narrower instead of hidden.
    ///
    /// Runs to a fixed point rather than in one pass: promoting one window shrinks
    /// the even share for everyone else, which can push a second window below
    /// *its* minimum, and stopping after the first promotion would leave that one
    /// overlapping.
    private static func share(_ total: CGFloat, among demands: [CGFloat]) -> [CGFloat] {
        let count = demands.count
        guard count > 0 else { return [] }
        guard total > 0 else { return Array(repeating: 0, count: count) }

        let asked = demands.reduce(0, +)
        // Everything at once will not fit. Hand the space out in proportion to
        // what was asked for: every pane ends up too small, which is a layout that
        // looks cramped, rather than panes that sum to more than the screen, which
        // is a layout that looks broken.
        guard asked < total else {
            guard asked > 0 else { return Array(repeating: total / CGFloat(count), count: count) }
            return demands.map { total * ($0 / asked) }
        }

        var reserved = [Bool](repeating: false, count: count)
        while true {
            let taken = zip(demands, reserved).reduce(CGFloat.zero) { $0 + ($1.1 ? $1.0 : 0) }
            let flexible = reserved.filter { !$0 }.count
            guard flexible > 0 else { break }

            let even = (total - taken) / CGFloat(flexible)
            guard let next = demands.indices.first(where: { !reserved[$0] && demands[$0] > even }) else { break }
            reserved[next] = true
        }

        let taken = zip(demands, reserved).reduce(CGFloat.zero) { $0 + ($1.1 ? $1.0 : 0) }
        let flexible = reserved.filter { !$0 }.count
        let even = flexible > 0 ? (total - taken) / CGFloat(flexible) : 0
        return demands.indices.map { reserved[$0] ? demands[$0] : even }
    }

    /// The fractions a split is allowed to take.
    ///
    /// The hard bounds keep a shortcut held down from collapsing a pane to nothing
    /// and leaving a window the user can no longer see or focus. Inside those, the
    /// two minimums pull the cut towards the middle from either side.
    private static func bounds(mine: CGFloat, theirs: CGFloat, extent: CGFloat) -> ClosedRange<CGFloat> {
        let floor: CGFloat = 0.1
        let ceiling: CGFloat = 0.9
        guard extent > 0 else { return floor ... ceiling }

        let low = min(max(mine / extent, floor), ceiling)
        let high = max(min(1 - theirs / extent, ceiling), floor)
        guard low <= high else {
            // Neither side can have what it asked for. Meet in proportion to the
            // two demands, so the bigger window still gets the bigger pane.
            let share = mine + theirs > 0 ? mine / (mine + theirs) : 0.5
            let meeting = min(max(share, floor), ceiling)
            return meeting ... meeting
        }
        return low ... high
    }

    // MARK: - Turning a rectangle into pixels

    /// Insets by the half-gap, without letting a narrow pane invert.
    ///
    /// `CGRect.insetBy` on a rectangle narrower than twice the inset returns a
    /// negative width, and every later step — rounding, comparing, writing it to a
    /// window — then behaves as if the rectangle had been mirrored.
    private static func inset(_ rect: CGRect, by amount: CGFloat) -> CGRect {
        let dx = min(amount, max(0, rect.width / 2 - 1))
        let dy = min(amount, max(0, rect.height / 2 - 1))
        return rect.insetBy(dx: dx, dy: dy)
    }

    /// Rounds every edge to a whole point.
    ///
    /// Deliberately not `CGRect.integral`, which floors the origin and ceilings
    /// the far edge — it *grows* every rectangle by up to a point on each side, so
    /// two panes that met exactly then overlapped by two points. Invisible at the
    /// default gaps and plainly wrong with the gaps turned off, which is exactly
    /// the kind of bug that only shows up on someone else's machine. Rounding both
    /// edges the same way means a shared edge stays shared.
    private static func snapped(_ rect: CGRect) -> CGRect {
        let minX = rect.minX.rounded()
        let minY = rect.minY.rounded()
        return CGRect(
            x: minX,
            y: minY,
            width: max(0, rect.maxX.rounded() - minX),
            height: max(0, rect.maxY.rounded() - minY)
        )
    }
}

nonisolated extension CGRect {
    /// Splits into two pieces at a fraction of the width or the height.
    /// The fraction is clamped so a shortcut held down cannot collapse a pane to
    /// nothing and leave a window the user can no longer see or focus.
    func split(atFraction fraction: CGFloat, vertical: Bool) -> (CGRect, CGRect) {
        let clamped = min(max(fraction, 0.1), 0.9)
        if vertical {
            let cut = width * clamped
            return (CGRect(x: minX, y: minY, width: cut, height: height),
                    CGRect(x: minX + cut, y: minY, width: width - cut, height: height))
        }
        let cut = height * clamped
        return (CGRect(x: minX, y: minY, width: width, height: cut),
                CGRect(x: minX, y: minY + cut, width: width, height: height - cut))
    }
}
