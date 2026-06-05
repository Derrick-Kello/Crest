//
//  DiskPilotApp.swift
//  DiskPilot
//

import SwiftUI

@main
struct DiskPilotApp: App {
    @State private var viewModel = DiskPilotViewModel()

    var body: some Scene {
        WindowGroup(id: "dashboard") {
            DashboardView()
                .environment(viewModel)
                .frame(minWidth: 960, minHeight: 640)
        }
        .defaultSize(width: 1100, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        MenuBarExtra {
            if viewModel.menuBarEnabled {
                MenuBarView()
                    .environment(viewModel)
            } else {
                Text("Menu bar disabled in Settings")
                    .padding()
            }
        } label: {
            if viewModel.menuBarEnabled {
                MenuBarIconLabel()
                    .environment(viewModel)
            } else {
                Image(systemName: "externaldrive.fill")
                    .font(.system(size: 16, weight: .medium))
                    .opacity(0.4)
            }
        }
        .menuBarExtraStyle(.window)
    }
}
