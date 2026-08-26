//
//  CrestApp.swift
//  Crest
//

import SwiftUI

@main
struct CrestApp: App {
    @State private var viewModel: CrestViewModel
    @Environment(\.openWindow) private var openWindow

    /// The migration has to run before anything else in the process exists.
    ///
    /// It used to be the first line of `CrestViewModel.init()`, which is too late and
    /// was wrong in a way that quietly lost data: the view model's stored properties are
    /// initialized *before* the body of its `init` runs, so `MeetingStore.shared` had
    /// already created an empty meetings folder under the new name by the time the
    /// migration looked to see whether one existed. Here there is no view model yet, and
    /// nothing has touched a store.
    ///
    /// `viewModel` is declared without a default value for the same reason — a default
    /// would be evaluated during this initializer regardless of what the body assigns.
    init() {
        LegacyMigration.runIfNeeded()
        _viewModel = State(initialValue: CrestViewModel())
    }

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
                        openUninstaller: { openWindow(id: "uninstall") },
                        openSettings: { openWindow(id: "settings") },
                        openMeetings: { openWindow(id: "meetings") }
                    )
                }
        }
        .menuBarExtraStyle(.window)
        // Keeps ⌘, and the Crest ▸ Settings… menu item pointing at the window
        // scene below, now that the `Settings` scene is gone.
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { openWindow(id: "settings") }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }

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

        // Meeting transcripts and their summaries. A window rather than a panel
        // section: a transcript is a document, and 360 points is not enough to
        // read one in.
        Window("Meeting Notes", id: "meetings") {
            MeetingsWindowView()
                .environment(viewModel)
        }
        .defaultSize(width: 900, height: 620)
        .commandsRemoved()

        // A `Window`, not SwiftUI's `Settings` scene.
        //
        // `Settings` has no programmatic opener — only `SettingsLink`, which is a
        // view, so nothing that is not already a view can open it. Measured from
        // this menu-bar app, the action behind that link
        // (`showSettingsWindow:`) found no target however it was sent: directly,
        // deferred a runloop pass, and through the menu item AppKit builds for
        // it. So picking "Crest Settings" in the command bar, or binding a
        // global shortcut to it, silently did nothing. A window scene has an id,
        // and `openWindow` opens it from anywhere.
        Window("Settings", id: "settings") {
            SettingsView()
                .environment(viewModel)
        }
        .defaultSize(width: 760, height: 560)
    }
}
