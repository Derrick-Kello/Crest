//
//  CleanupConfirmationSheet.swift
//  DiskPilot
//

import SwiftUI

struct CleanupConfirmationSheet: View {
    let preview: CleanupPreview
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Confirm Cleanup", systemImage: "trash.circle")
                .font(.title2.bold())

            Text("You are about to clean **\(preview.target.displayName)**.")
                .foregroundStyle(.secondary)

            HStack {
                Text("Estimated space reclaimed")
                Spacer()
                Text(DiskUsageModel.formatBytes(preview.estimatedBytes))
                    .font(.headline.monospacedDigit())
            }

            Text(preview.target.path)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)

            HStack {
                Label(preview.target.riskLevel.rawValue, systemImage: preview.target.riskLevel.iconName)
                    .foregroundStyle(preview.target.riskLevel == .safe ? .green : .orange)
                Spacer()
            }

            HStack {
                Button("Cancel", role: .cancel, action: onCancel)
                Spacer()
                Button("Clean Now", role: .destructive, action: onConfirm)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}
