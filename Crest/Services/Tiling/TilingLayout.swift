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
    static func frames(
        count: Int,
        in area: CGRect,
        mode: LayoutMode,
        gap: CGFloat,
        outerGap: CGFloat,
        ratios: [CGFloat] = [],
        mainCount: Int = 1
    ) -> [CGRect] {
        guard count > 0 else { return [] }

        // Insetting the container by the outer gap less half the inner gap means
        // that after every frame is inset by half the inner gap below, the space
        // between two windows is exactly `gap` and the space to the screen edge is
        // exactly `outerGap`. Doing it in one step at the end would make the edges
        // and the seams disagree by a factor of two.
        let container = area.insetBy(dx: outerGap - gap / 2, dy: outerGap - gap / 2)
        guard container.width > 0, container.height > 0 else { return [] }

        let raw: [CGRect] = switch mode {
        case .dwindle: dwindle(count: count, in: container, ratios: ratios, depth: 0)
        case .tall: mainStack(count: count, in: container, ratio: ratios.first ?? 0.5, mainCount: mainCount, vertical: true)
        case .wide: mainStack(count: count, in: container, ratio: ratios.first ?? 0.5, mainCount: mainCount, vertical: false)
        case .monocle: Array(repeating: container, count: count)
        }

        return raw.map { $0.insetBy(dx: gap / 2, dy: gap / 2).integral }
    }

    // MARK: - Dwindle

    /// The recursive spiral. The last window takes whatever is left, which is what
    /// keeps the layout gapless however the ratios were dragged.
    private static func dwindle(count: Int, in rect: CGRect, ratios: [CGFloat], depth: Int) -> [CGRect] {
        guard count > 1 else { return [rect] }

        let ratio = ratios.indices.contains(depth) ? ratios[depth] : 0.5
        // Split across the longer axis, so panes tend back towards square instead
        // of degenerating into slivers as the count climbs.
        let (first, rest) = rect.width >= rect.height
            ? rect.split(atFraction: ratio, vertical: true)
            : rect.split(atFraction: ratio, vertical: false)

        return [first] + dwindle(count: count - 1, in: rest, ratios: ratios, depth: depth + 1)
    }

    // MARK: - Main and stack

    private static func mainStack(count: Int, in rect: CGRect, ratio: CGFloat, mainCount: Int, vertical: Bool) -> [CGRect] {
        let mains = max(1, min(mainCount, count))
        guard count > mains else { return divide(rect, into: count, vertical: !vertical) }

        let (mainArea, stackArea) = rect.split(atFraction: ratio, vertical: vertical)
        return divide(mainArea, into: mains, vertical: !vertical)
            + divide(stackArea, into: count - mains, vertical: !vertical)
    }

    /// Cuts a rectangle into `count` equal parts. `vertical` splits left-to-right.
    private static func divide(_ rect: CGRect, into count: Int, vertical: Bool) -> [CGRect] {
        guard count > 0 else { return [] }
        return (0 ..< count).map { index in
            let fraction = CGFloat(index) / CGFloat(count)
            let extent = CGFloat(1) / CGFloat(count)
            return vertical
                ? CGRect(x: rect.minX + rect.width * fraction, y: rect.minY,
                         width: rect.width * extent, height: rect.height)
                : CGRect(x: rect.minX, y: rect.minY + rect.height * fraction,
                         width: rect.width, height: rect.height * extent)
        }
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
