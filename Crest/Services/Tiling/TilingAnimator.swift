//
//  TilingAnimator.swift
//  Crest
//

import AppKit
import ApplicationServices
import QuartzCore

/// Moves windows to their new frames over a few frames instead of in one jump.
///
/// macOS gives no way to animate another application's window: there is no
/// implicit animation behind `kAXPositionAttribute`, and Core Animation cannot
/// reach a layer it does not own. The only thing available is to write the frame
/// repeatedly, which is what every tiler that animates on this platform does.
///
/// That makes the frame budget the whole design. Each write is a synchronous IPC
/// round trip into the owning application, so the cost is windows × steps, and an
/// unresponsive app pays for it on Crest's main thread. So: a short duration, a
/// step count that shrinks as the window count grows, one write per step rather
/// than the position-size-position dance, and the full careful write saved for
/// the last step where it is the frame that has to be exactly right.
@MainActor
final class TilingAnimator {
    static let shared = TilingAnimator()

    /// One window on its way somewhere.
    private struct Track {
        let element: AXUIElement
        let from: CGRect
        let to: CGRect
    }

    private var tracks: [CGWindowID: Track] = [:]
    private var timer: Timer?
    private var startedAt: CFTimeInterval = 0
    private var duration: CFTimeInterval = 0
    private var completion: (() -> Void)?

    private init() {}

    /// How long a move of `count` windows will take, so the caller can hold off
    /// reacting to its own writes for exactly that long.
    ///
    /// Shrinks with the window count on purpose. Two windows can afford a leisurely
    /// glide; nine cannot, because the same wall-clock time has to cover four and a
    /// half times the IPC and the animation would start dropping frames — which
    /// looks worse than not animating at all.
    static func duration(forCount count: Int) -> CFTimeInterval {
        guard count > 0 else { return 0 }
        return count <= 3 ? 0.20 : (count <= 6 ? 0.16 : 0.12)
    }

    var isRunning: Bool { timer != nil }

    /// Writes every window to its frame, animating there when asked.
    ///
    /// `completion` runs once, after the last write, whether or not anything was
    /// animated — the engine uses it to know the desktop has stopped moving.
    func move(_ moves: [(window: TilingWindow, frame: CGRect)], animated: Bool, completion: @escaping () -> Void) {
        stop()

        // Windows already where they belong are skipped entirely. This is the
        // single biggest thing keeping the desktop still: an Accessibility
        // notification fires on nearly every click, each one ends in a layout
        // pass, and without this check every pass rewrote every frame — which is
        // what made a tiled desktop shimmer whenever anything happened on it.
        let work = moves.compactMap { move -> (TilingWindow, CGRect, CGRect)? in
            guard let current = move.window.frame else { return nil }
            guard !current.isNearly(move.frame) else { return nil }
            return (move.window, current, move.frame)
        }

        guard !work.isEmpty else {
            completion()
            return
        }

        guard animated, work.count <= 10 else {
            for (window, _, frame) in work { AX.setFrame(frame, of: window.element) }
            completion()
            return
        }

        tracks = Dictionary(uniqueKeysWithValues: work.map { window, from, to in
            (window.id, Track(element: window.element, from: from, to: to))
        })
        self.completion = completion
        duration = Self.duration(forCount: work.count)
        startedAt = CACurrentMediaTime()

        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { _ in
            MainActor.assumeIsolated { TilingAnimator.shared.step() }
        }
        // `.common`, so the animation keeps running while a menu is open or the
        // user is dragging something — both are exactly when a window moves.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Abandons an animation in flight, leaving windows wherever they got to.
    ///
    /// Called before starting a new one: two animations writing the same window
    /// interleave into a jitter, and the second one's destination is the only one
    /// that is still correct anyway.
    func stop() {
        timer?.invalidate()
        timer = nil
        tracks = [:]
        completion = nil
    }

    private func step() {
        let elapsed = CACurrentMediaTime() - startedAt
        let progress = duration > 0 ? min(elapsed / duration, 1) : 1

        if progress >= 1 {
            let finished = tracks
            let done = completion
            stop()
            // The final write is the careful one — position, size, position — so
            // that a window which clamped an intermediate frame still lands
            // exactly where the layout put it.
            for track in finished.values { AX.setFrame(track.to, of: track.element) }
            done?()
            return
        }

        let eased = Self.easeOut(progress)
        for track in tracks.values {
            AX.setFrameQuickly(track.from.interpolated(to: track.to, at: eased), of: track.element)
        }
    }

    /// Cubic ease-out: fast off the mark, settling into place. The shape that
    /// reads as "the window moved" rather than "the window is being dragged".
    private static func easeOut(_ t: CFTimeInterval) -> CGFloat {
        let clamped = min(max(t, 0), 1)
        return CGFloat(1 - pow(1 - clamped, 3))
    }
}

private extension CGRect {
    func interpolated(to other: CGRect, at fraction: CGFloat) -> CGRect {
        CGRect(
            x: minX + (other.minX - minX) * fraction,
            y: minY + (other.minY - minY) * fraction,
            width: width + (other.width - width) * fraction,
            height: height + (other.height - height) * fraction
        ).integral
    }

    /// Within a point on every edge, which is as close as a window that rounds its
    /// own size can be asked to get.
    func isNearly(_ other: CGRect) -> Bool {
        abs(minX - other.minX) <= 1
            && abs(minY - other.minY) <= 1
            && abs(width - other.width) <= 1
            && abs(height - other.height) <= 1
    }
}
