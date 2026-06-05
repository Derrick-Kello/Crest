//
//  SystemInsightsView.swift
//  DiskPilot
//

import SwiftUI

struct SystemInsightsView: View {
    @Environment(DiskPilotViewModel.self) private var viewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let message = viewModel.notificationMessage {
                    insightBanner(message, icon: "bell.badge", color: .orange)
                }

                insightBanner(
                    "Scans ~/Library, Developer folders, npm, Docker, and Downloads. Protected paths are never deleted.",
                    icon: "shield.checkered",
                    color: .blue
                )

                if let usage = viewModel.diskUsage {
                    let devSize = usage.categoryBreakdown
                        .first { $0.category == .developer }?.size ?? 0
                    if devSize > 5 * 1024 * 1024 * 1024 {
                        insightBanner(
                            "Developer storage is \(DiskUsageModel.formatBytes(devSize)). Consider cleaning caches.",
                            icon: "hammer",
                            color: .orange
                        )
                    }
                }

                Text("Cleanup Log")
                    .font(.headline)

                if viewModel.cleanupLog.isEmpty {
                    Text("No cleanup actions yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.cleanupLog) { entry in
                        HStack(alignment: .top) {
                            Image(systemName: entry.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(entry.success ? .green : .red)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.action)
                                    .font(.body.weight(.medium))
                                Text(entry.path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(entry.timestamp.formatted())
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Text(DiskUsageModel.formatBytes(entry.bytesReclaimed))
                                .monospacedDigit()
                        }
                        .padding(12)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("System Insights")
    }

    private func insightBanner(_ text: String, icon: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.title3)
            Text(text)
                .font(.body)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
}
