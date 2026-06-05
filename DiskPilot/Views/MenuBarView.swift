//
//  MenuBarView.swift
//  DiskPilot
//

import SwiftUI

struct MenuBarView: View {
    @Environment(DiskPilotViewModel.self) private var viewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let usage = viewModel.diskUsage {
                HStack {
                    DiskUsageProgressRing(
                        percentageUsed: usage.percentageUsed,
                        health: viewModel.healthStatus
                    )
                    .scaleEffect(0.7)
                    VStack(alignment: .leading) {
                        Text("\(usage.formattedFreeSpace) free")
                            .font(.headline)
                        Text("\(usage.formattedUsedSpace) used of \(usage.formattedTotalCapacity)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                Divider()
            }

            menuButton("Open Dashboard", icon: "macwindow") {
                openWindow(id: "dashboard")
                viewModel.openDashboard()
            }
            menuButton("Run Quick Scan", icon: "arrow.clockwise") {
                Task { await viewModel.runScan() }
            }
            menuButton("Clean Developer Cache", icon: "sparkles") {
                Task { await viewModel.quickCleanDeveloperCaches() }
            }
            menuButton("Clean Docker", icon: "shippingbox") {
                Task { await viewModel.pruneDocker() }
            }
            menuButton("View Storage Report", icon: "doc.text") {
                viewModel.selectedSection = .storageMap
                openWindow(id: "dashboard")
            }
            Divider()
            menuButton("Quit DiskPilot", icon: "power") {
                NSApplication.shared.terminate(nil)
            }
        }
        .frame(width: 280)
    }

    private func menuButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
