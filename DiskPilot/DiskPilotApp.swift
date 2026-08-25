//
//  DiskPilotApp.swift
//  DiskPilot
//

import SwiftUI

@main
struct DiskPilotApp: App {
    @State private var viewModel = DiskPilotViewModel()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        // The menu bar is the app. There is no `WindowGroup`, so nothing is built,
        // laid out, or retained until the user opens the panel — which is most of
        // the difference in idle memory against the old always-on dashboard window.
        MenuBarExtra {
            PanelView()
                .environment(viewModel)
        } label: {
            MenuBarIconLabel()
                .environment(viewModel)
                .task {
                    // `openWindow` only exists inside a scene, so the view model is
                    // handed a closure here rather than reaching for a window itself.
                    viewModel.applicationDidLaunch(
                        openReview: { openWindow(id: "review") },
                        openUninstaller: { openWindow(id: "uninstall") }
                    )
                }
        }
        .menuBarExtraStyle(.window)

        // `Window`, not `WindowGroup`: one review window, opened on demand, and no
        // instance exists at launch.
        Window("Review", id: "review") {
            CleanerReviewView()
                .environment(viewModel)
        }
        .defaultSize(width: 760, height: 540)
        .commandsRemoved()

        // Same reasoning as the review window: opened on demand, never at launch,
        // and only one of it however many times the shortcut is pressed.
        Window("Uninstall an app", id: "uninstall") {
            UninstallerView()
                .environment(viewModel)
        }
        .defaultSize(width: 680, height: 520)
        .commandsRemoved()

        Settings {
            SettingsView()
                .environment(viewModel)
        }
    }
}
