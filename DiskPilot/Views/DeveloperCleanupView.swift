//
//  DeveloperCleanupView.swift
//  DiskPilot
//

import SwiftUI

struct DeveloperCleanupView: View {
    @Environment(DiskPilotViewModel.self) private var viewModel

    var body: some View {
        @Bindable var viewModel = viewModel

        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(viewModel.developerTargets) { target in
                    cleanupRow(target)
                }
            }
            .padding(24)
        }
        .navigationTitle("Developer Cleanup")
        .sheet(isPresented: $viewModel.showCleanupConfirmation) {
            if let preview = viewModel.cleanupPreview {
                CleanupConfirmationSheet(
                    preview: preview,
                    onConfirm: { Task { await viewModel.confirmCleanup() } },
                    onCancel: {
                        viewModel.showCleanupConfirmation = false
                        viewModel.cleanupPreview = nil
                    }
                )
            }
        }
    }

    private func cleanupRow(_ target: DeveloperCleanupTarget) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(target.displayName)
                    .font(.headline)
                Text(target.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(target.formattedSize)
                    .font(.body.monospacedDigit())
                Label(target.riskLevel.rawValue, systemImage: target.riskLevel.iconName)
                    .font(.caption)
                    .foregroundStyle(target.riskLevel == .safe ? .green : .orange)
            }
            Button("Clean") {
                viewModel.requestCleanup(for: target)
            }
            .disabled(target.cleanupCommand == nil)
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
