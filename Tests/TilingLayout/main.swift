import CoreGraphics
import Foundation

var failures = 0
func check(_ label: String, _ condition: Bool) {
    print(condition ? "  ok   \(label)" : "  FAIL \(label)")
    if !condition { failures += 1 }
}

/// A 16:10 screen with the menu bar already taken off, which is the shape the
/// engine actually hands the layout.
let screen = CGRect(x: 0, y: 37, width: 1920, height: 1043)
let gap: CGFloat = 8
let outer: CGFloat = 12

func frames(_ count: Int, _ mode: LayoutMode, ratios: [CGFloat] = [], mainCount: Int = 1) -> [CGRect] {
    TilingLayout.frames(
        count: count, in: screen, mode: mode,
        gap: gap, outerGap: outer, ratios: ratios, mainCount: mainCount
    )
}

/// Two rectangles overlap when they share any area at all.
///
/// Deliberately strict. This used to allow a point of slop on each axis, which
/// hid a real bug: `CGRect.integral` grew every pane outward, so with the gaps
/// turned off two neighbours ended up sharing a one-point seam down their whole
/// length. A seam that thin is invisible on a screenshot and perfectly visible
/// when the window on top of it is the one you are trying to read.
func overlaps(_ a: CGRect, _ b: CGRect) -> Bool {
    let shared = a.intersection(b)
    return !shared.isNull && shared.width > 0 && shared.height > 0
}

func anyOverlap(_ rects: [CGRect]) -> Bool {
    for i in rects.indices {
        for j in rects.indices where j > i {
            if overlaps(rects[i], rects[j]) { return true }
        }
    }
    return false
}

print("every window gets a frame")
for mode in LayoutMode.allCases {
    for count in 1 ... 8 {
        check("\(mode.rawValue) lays out \(count)", frames(count, mode).count == count)
    }
}
check("no windows, no frames", frames(0, .dwindle).isEmpty)

print("panes never overlap")
// Monocle is excluded on purpose: stacking every window on the same rectangle is
// what that layout is.
for mode in LayoutMode.allCases where mode != .monocle {
    for count in 2 ... 8 {
        check("\(mode.rawValue) keeps \(count) panes apart", !anyOverlap(frames(count, mode)))
    }
}

print("panes stay on the screen")
for mode in LayoutMode.allCases {
    for count in 1 ... 8 {
        let inside = frames(count, mode).allSatisfy { screen.insetBy(dx: -1, dy: -1).contains($0) }
        check("\(mode.rawValue) keeps \(count) on screen", inside)
    }
}

print("gaps are the gaps that were asked for")
let two = frames(2, .dwindle)
check("outer gap on the left edge", abs(two[0].minX - (screen.minX + outer)) <= 1)
check("outer gap on the top edge", abs(two[0].minY - (screen.minY + outer)) <= 1)
check("outer gap on the right edge", abs(two[1].maxX - (screen.maxX - outer)) <= 1)
check("inner gap between the two panes", abs(two[1].minX - two[0].maxX - gap) <= 1)

let zeroGap = TilingLayout.frames(count: 2, in: screen, mode: .dwindle, gap: 0, outerGap: 0)
check("no gaps means the panes touch", abs(zeroGap[1].minX - zeroGap[0].maxX) <= 1)
check("no gaps means the screen is filled", abs(zeroGap[0].minX - screen.minX) <= 1)

print("dwindle splits the longer axis")
// The screen is wider than it is tall, so the first cut is vertical and the two
// panes end up side by side rather than stacked.
check("first cut on a wide screen is vertical", two[0].maxX <= two[1].minX + 1)
// After that cut each half is taller than it is wide, so the second cut is
// horizontal — this is what makes four windows a spiral instead of four columns.
let four = frames(4, .dwindle)
check("second cut is horizontal", four[1].maxY <= four[2].minY + 1)
// Area, not width: the second cut is horizontal, so pane 1 keeps pane 0's width
// and loses half its height. Checking width here passes on a tall screen and
// fails on a wide one, which is the wrong kind of test.
check("dwindle halves the area each time", four[0].width * four[0].height > four[1].width * four[1].height)

print("ratios move the split")
let biased = frames(2, .dwindle, ratios: [0.75])
check("a 75% ratio gives the first pane three quarters",
      abs(biased[0].width / (biased[0].width + biased[1].width) - 0.75) < 0.02)
// A shortcut held down must not be able to collapse a pane to nothing, because a
// window with no width cannot be seen or clicked back into existence.
let collapsed = frames(2, .dwindle, ratios: [0.0])
check("an impossible ratio is clamped, not obeyed", collapsed[0].width > 100)
let inverted = frames(2, .dwindle, ratios: [1.5])
check("a ratio over one is clamped too", inverted[1].width > 100)

print("tall and wide")
let tall = frames(3, .tall)
check("tall puts the main pane on the left", tall[0].minX < tall[1].minX)
check("tall stacks the rest vertically", tall[1].maxY <= tall[2].minY + 1)
check("tall main pane is the tallest", tall[0].height > tall[1].height)

let wide = frames(3, .wide)
check("wide puts the main pane on top", wide[0].minY < wide[1].minY)
check("wide lays the rest out across", wide[1].maxX <= wide[2].minX + 1)

let twoMain = frames(4, .tall, mainCount: 2)
check("two windows share the main pane", abs(twoMain[0].maxX - twoMain[1].maxX) <= 1)
check("the main pane is split vertically", twoMain[0].maxY <= twoMain[1].minY + 1)
// One window per side and none left over is still a main-and-stack layout, not a
// crash: `mainCount` is clamped against the window count.
check("more main slots than windows is survivable", frames(2, .tall, mainCount: 9).count == 2)

print("monocle")
let monocle = frames(3, .monocle)
check("every window gets the same rectangle", monocle[0] == monocle[1] && monocle[1] == monocle[2])
check("and it is the whole screen", abs(monocle[0].width - (screen.width - outer * 2)) <= 2)

print("degenerate areas")
// A screen smaller than the gaps has no room for a window, and the layout has to
// say so rather than hand back a negative rectangle.
let sliver = TilingLayout.frames(count: 2, in: CGRect(x: 0, y: 0, width: 10, height: 10), mode: .dwindle, gap: gap, outerGap: outer)
check("no room means no frames", sliver.isEmpty)

print("frames are whole pixels")
check("every frame is integral", frames(5, .dwindle).allSatisfy { $0 == $0.integral })

print("panes never overlap, whatever the settings")
// The sweep the hand-written cases above kept missing. Every combination of
// screen shape, gap, outer gap, layout, window count and main-pane count, checked
// for the one property that matters more than any of them: two windows are never
// in the same place.
let shapes = [
    CGRect(x: 0, y: 37, width: 1920, height: 1043),
    CGRect(x: 0, y: 37, width: 1440, height: 863),
    CGRect(x: 0, y: 37, width: 1280, height: 723),
    CGRect(x: 0, y: 37, width: 1512, height: 945),
    CGRect(x: 0, y: 37, width: 1080, height: 1883),
]
var sweptOverlaps = 0
var sweptOffscreen = 0
var sweptEmpty = 0
for shape in shapes {
    for innerGap in [CGFloat(0), 1, 8, 12, 24, 40] {
        for outerGap in [CGFloat(0), 4, 12, 60] {
            for mode in LayoutMode.allCases where mode != .monocle {
                for count in 1 ... 9 {
                    for mainCount in 1 ... 3 {
                        let laid = TilingLayout.frames(
                            count: count, in: shape, mode: mode,
                            gap: innerGap, outerGap: outerGap, mainCount: mainCount
                        )
                        guard !laid.isEmpty else { continue }
                        if anyOverlap(laid) { sweptOverlaps += 1 }
                        if laid.contains(where: { !shape.insetBy(dx: -1, dy: -1).contains($0) }) { sweptOffscreen += 1 }
                        if laid.contains(where: { $0.width <= 0 || $0.height <= 0 }) { sweptEmpty += 1 }
                    }
                }
            }
        }
    }
}
check("no overlaps anywhere in the sweep", sweptOverlaps == 0)
check("nothing lands off the screen", sweptOffscreen == 0)
check("no pane collapses to nothing", sweptEmpty == 0)

// The specific case the sweep was written for: gaps off, four or more windows.
for count in 2 ... 9 {
    let gapless = TilingLayout.frames(count: count, in: screen, mode: .dwindle, gap: 0, outerGap: 0)
    check("\(count) gapless panes do not overlap", !anyOverlap(gapless))
}

print("windows that will not shrink get the room they need")
// A window with a hard minimum used to be handed an even share, refuse it, and
// sit on top of its neighbour. Reserving the width it is going to take anyway is
// what turns that into a narrower neighbour instead of a hidden one.
let stubborn = CGSize(width: 900, height: 400)
let reserved = TilingLayout.frames(
    count: 3, in: screen, mode: .tall, gap: gap, outerGap: outer,
    minimums: [stubborn, .zero, .zero]
)
check("the stubborn window gets its minimum", reserved[0].width >= stubborn.width)
check("and its neighbours are narrower, not covered", !anyOverlap(reserved))
check("and the panes still add up to the screen",
      abs(reserved.map(\.width).max()! + reserved[1].width + gap - (screen.width - outer * 2)) <= 2)

// Same thing one level down: a minimum on a stacked window has to come out of the
// windows it is stacked with, not out of the pane beside it.
let stacked = TilingLayout.frames(
    count: 4, in: screen, mode: .tall, gap: gap, outerGap: outer,
    minimums: [.zero, CGSize(width: 200, height: 600), .zero, .zero]
)
check("a tall minimum is honoured down the stack", stacked[1].height >= 600)
check("and nothing overlaps because of it", !anyOverlap(stacked))

// Dwindle honours them too, at every depth, and still never overlaps.
for depth in 0 ..< 5 {
    var wants = [CGSize](repeating: .zero, count: 6)
    wants[depth] = CGSize(width: 700, height: 500)
    let spiral = TilingLayout.frames(
        count: 6, in: screen, mode: .dwindle, gap: gap, outerGap: outer, minimums: wants
    )
    check("dwindle keeps 6 apart with a minimum at \(depth)", !anyOverlap(spiral))
}

// Two windows that both want more than half. Neither can have it, and the only
// wrong answer is to give it to both and let them overlap.
let impossible = TilingLayout.frames(
    count: 2, in: screen, mode: .tall, gap: gap, outerGap: outer,
    minimums: [CGSize(width: 1600, height: 400), CGSize(width: 1600, height: 400)]
)
check("impossible minimums are shared out, not both granted", !anyOverlap(impossible))
check("and both windows still get a usable pane", impossible.allSatisfy { $0.width > 100 })

// A minimum bigger than the whole screen must not push a pane off it.
let absurd = TilingLayout.frames(
    count: 3, in: screen, mode: .dwindle, gap: gap, outerGap: outer,
    minimums: [CGSize(width: 9000, height: 9000), .zero, .zero]
)
check("an absurd minimum stays on screen",
      absurd.allSatisfy { screen.insetBy(dx: -1, dy: -1).contains($0) })
check("and does not swallow its neighbours", !anyOverlap(absurd))

print(failures == 0 ? "\nall passed" : "\n\(failures) failed")
exit(failures == 0 ? 0 : 1)
