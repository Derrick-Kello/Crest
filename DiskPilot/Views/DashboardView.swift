//
//  DashboardView.swift
//  DiskPilot
//

import SwiftUI

struct DashboardView: View {
    @Environment(DiskPilotViewModel.self) private var viewModel

    var body: some View {
        @Bindable var viewModel = viewModel

        NavigationSplitView {
            List(DashboardSection.allCases, selection: $viewModel.selectedSection) { section in
                Label(section.rawValue, systemImage: section.iconName)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            Group {
                switch viewModel.selectedSection {
                case .overview:
                    OverviewView()
                case .storageFindings:
                    StorageFindingsView()
                case .storageMap:
                    StorageMapView()
                case .developerCleanup:
                    DeveloperCleanupView()
                case .docker:
                    DockerManagerView()
                case .systemInsights:
                    SystemInsightsView()
                case .settings:
                    SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await viewModel.runScan() }
                } label: {
                    if viewModel.isScanning {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Scan", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(viewModel.isScanning)
            }
        }
        .task {
            viewModel.bootstrapIfNeeded()
        }
        .alert("Error", isPresented: $viewModel.showErrorAlert) {
            Button("OK") { viewModel.dismissError() }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}
