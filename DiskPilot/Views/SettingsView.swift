//
//  SettingsView.swift
//  DiskPilot
//

import SwiftUI

struct SettingsView: View {
    @Environment(DiskPilotViewModel.self) private var viewModel

    var body: some View {
        @Bindable var viewModel = viewModel

        Form {
            Section("Menu Bar") {
                Toggle("Show menu bar utility", isOn: $viewModel.menuBarEnabled)
            }

            Section("Scanning") {
                Picker("Auto scan interval", selection: $viewModel.autoScanIntervalSeconds) {
                    Text("10 seconds").tag(10)
                    Text("30 seconds").tag(30)
                    Text("60 seconds").tag(60)
                }
            }

            Section("Cleanup Safety") {
                Picker("Safety level", selection: $viewModel.safetyLevel) {
                    ForEach(CleanupSafetyLevel.allCases) { level in
                        Text(level.rawValue).tag(level)
                    }
                }
                Text("Conservative blocks moderate-risk targets like Android emulator storage.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Docker") {
                Toggle("Docker integration", isOn: $viewModel.dockerIntegrationEnabled)
            }
        }
        .onChange(of: viewModel.menuBarEnabled) { _, _ in viewModel.persistSettings() }
        .onChange(of: viewModel.autoScanIntervalSeconds) { _, _ in
            viewModel.persistSettings()
            viewModel.startPeriodicRefresh()
        }
        .onChange(of: viewModel.safetyLevel) { _, _ in viewModel.persistSettings() }
        .onChange(of: viewModel.dockerIntegrationEnabled) { _, _ in viewModel.persistSettings() }
        .formStyle(.grouped)
        .padding(24)
        .navigationTitle("Settings")
    }
}
