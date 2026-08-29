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

/// Two rectangles overlap when they share more than a rounding error of area.
func overlaps(_ a: CGRect, _ b: CGRect) -> Bool {
    let shared = a.intersection(b)
    return !shared.isNull && shared.width > 1 && shared.height > 1
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

print(failures == 0 ? "\nall passed" : "\n\(failures) failed")
exit(failures == 0 ? 0 : 1)
