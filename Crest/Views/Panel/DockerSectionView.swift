//
//  DockerSectionView.swift
//  Crest
//

import SwiftUI

/// Docker keeps its own storage outside anything the cleaner can safely trash, so
/// it gets its own row and its own verb: prune, via the Docker CLI.
struct DockerSectionView: View {
    @Environment(CrestViewModel.self) private var viewModel

    private var stats: DockerStats { viewModel.dockerStats }

    var body: some View {
        PanelCard(section: .docker) {
            if viewModel.isLoadingDocker {
                ProgressView().controlSize(.mini)
            } else if stats.isDockerAvailable, stats.totalSize > 0 {
                Text(stats.formattedTotal)
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        } content: {
            VStack(alignment: .leading, spacing: 6) {
                if !stats.isDockerAvailable {
                    Text("Docker isn't running, or the CLI isn't on your PATH.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        Task { await viewModel.refreshDocker() }
                    } label: {
                        Text("Check again").font(.system(size: 10))
                    }
                    .buttonStyle(.link)
                } else {
                    PanelRow(title: "Images", iconName: "square.stack.3d.up") {
                        SizeLabel(bytes: stats.imagesSize)
                    }
                    PanelRow(title: "Containers", iconName: "shippingbox") {
                        SizeLabel(bytes: stats.containersSize)
                    }
                    PanelRow(title: "Volumes", iconName: "cylinder.split.1x2") {
                        SizeLabel(bytes: stats.volumesSize)
                    }

                    if stats.reclaimableSize > 0 {
                        Divider().padding(.vertical, 2)
                        HStack {
                            Text("\(stats.formattedReclaimable) reclaimable")
                                .font(.system(size: 11))
                                .foregroundStyle(.orange)
                            Spacer()
                            Button {
                                Task { await viewModel.pruneDocker() }
                            } label: {
                                Text("Prune").font(.system(size: 11, weight: .medium))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(viewModel.isLoadingDocker)
                        }
                        Text("Runs `docker system prune -f`: stopped containers, dangling images and unused networks.")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}
