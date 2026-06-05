//
//  DockerManagerView.swift
//  DiskPilot
//

import SwiftUI

struct DockerManagerView: View {
    @Environment(DiskPilotViewModel.self) private var viewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if viewModel.dockerStats.isDockerAvailable {
                    statsGrid
                    actions
                    if !viewModel.dockerStats.rawOutput.isEmpty {
                        Text("docker system df")
                            .font(.headline)
                        Text(viewModel.dockerStats.rawOutput)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                    }
                } else {
                    ContentUnavailableView(
                        "Docker not available",
                        systemImage: "shippingbox",
                        description: Text("Install Docker Desktop or enable integration in Settings.")
                    )
                }
            }
            .padding(24)
        }
        .navigationTitle("Docker Manager")
    }

    private var statsGrid: some View {
        Grid(horizontalSpacing: 16, verticalSpacing: 16) {
            statCard("Images", value: DiskUsageModel.formatBytes(viewModel.dockerStats.imagesSize), icon: "square.stack.3d.up")
            statCard("Containers", value: DiskUsageModel.formatBytes(viewModel.dockerStats.containersSize), icon: "cube")
            statCard("Volumes", value: DiskUsageModel.formatBytes(viewModel.dockerStats.volumesSize), icon: "externaldrive")
            statCard("Reclaimable", value: viewModel.dockerStats.formattedReclaimable, icon: "arrow.down.circle")
        }
    }

    private func statCard(_ title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.bold().monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button {
                Task { await viewModel.refreshDockerStats() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            Button {
                Task { await viewModel.pruneDocker() }
            } label: {
                Label("Prune System", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
