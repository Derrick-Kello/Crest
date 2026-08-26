//
//  OnboardingWindow.swift
//  Crest
//

import AppKit
import SwiftUI

/// Puts the first-run flow on screen.
///
/// An `NSWindow` built here rather than a SwiftUI `Window` scene for the same
/// reason the command bar is a panel: an `LSUIElement` app has to raise its own
/// activation policy before a window it opens can take the keyboard, and a scene
/// gives no hook early enough to do that.
@MainActor
final class OnboardingController {
    static let shared = OnboardingController()

    private var window: NSWindow?
    private var closeObserver: NSObjectProtocol?

    private init() {}

    var isVisible: Bool { window?.isVisible ?? false }

    func show(viewModel: CrestViewModel) {
        if let window {
            AppActivation.beginForeground("onboarding")
            window.makeKeyAndOrderFront(nil)
            return
        }

        let controller = NSHostingController(
            rootView: OnboardingView(onFinish: { [weak self] in self?.finish() })
                .environment(viewModel)
        )

        let window = NSWindow(contentViewController: controller)
        window.title = "Welcome to Crest"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.styleMask.remove(.resizable)
        window.backgroundColor = .clear
        window.center()
        window.isReleasedWhenClosed = false

        // Closing with the red button counts as finishing: the flow is skippable
        // at every step, so there is nothing left to come back for.
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.markComplete() }
        }

        self.window = window
        AppActivation.beginForeground("onboarding")
        window.makeKeyAndOrderFront(nil)
    }

    private func finish() {
        window?.close()
    }

    private func markComplete() {
        Preferences.completedOnboardingVersion = OnboardingController.currentVersion
        if let closeObserver {
            NotificationCenter.default.removeObserver(closeObserver)
            self.closeObserver = nil
        }
        window = nil
        AppActivation.endForeground("onboarding")
    }

    /// Bumped when a release adds steps worth showing to people who already
    /// onboarded. Anyone below this number sees the flow once at next launch.
    static let currentVersion = 1

    static var isPending: Bool {
        Preferences.completedOnboardingVersion < currentVersion
    }
}
