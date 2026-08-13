//
//  DiskSectionView.swift
//  DiskPilot
//

import SwiftUI

struct DiskSectionView: View {
    @Environment(DiskPilotViewModel.self) private var viewModel

    private var volume: VolumeSnapshot { viewModel.volume }

    /// What the cleaner found, drawn on top of the used portion so the user can see
    /// the reclaimable slice in the context of the whole disk rather than as an
    /// abstract number somewhere else in the panel.
    private var cleanableBytes: UInt64 { viewModel.scan?.totalBytes ?? 0 }

    var body: some View {
        PanelCard(section: .disk) {
            Text(volume.formattedFree)
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(viewModel.health.color)
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                CapacityBar(
                    total: volume.totalCapacity,
                    segments: [
                        .init(id: "used", bytes: volume.usedSpace - min(volume.usedSpace, cleanableBytes),
                              color: viewModel.health.color.opacity(0.85)),
                        .init(id: "cleanable", bytes: min(volume.usedSpace, cleanableBytes),
                              color: .orange),
                    ]
                )

                HStack(spacing: 4) {
                    Text("\(volume.formattedFree) free")
                        .font(.system(size: 11, weight: .medium))
                    Text("of \(volume.formattedTotal)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if cleanableBytes > 0 {
                        Circle().fill(.orange).frame(width: 6, height: 6)
                        Text("\(ByteFormat.string(cleanableBytes)) cleanable")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }

                if viewModel.health == .critical {
                    Text("macOS needs free space for updates and swap. Running a scan is a good next step.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
