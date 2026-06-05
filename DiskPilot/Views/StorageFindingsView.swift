//
//  StorageFindingsView.swift
//  DiskPilot
//

import SwiftUI

struct StorageFindingsView: View {
    @Environment(DiskPilotViewModel.self) private var viewModel

    @State private var filterCategory: StorageFindingCategory?
    @State private var filterRisk: StorageRiskLevel?
    @State private var cachedFindings: [StorageFinding] = []

    /// Recomputed only when the deep scan result or filters change.
    private func rebuildFindings() {
        guard let result = viewModel.deepScanResult else {
            cachedFindings = []
            return
        }
        cachedFindings = result.findings.filter { finding in
            let categoryMatch = filterCategory == nil || finding.category == filterCategory
            let riskMatch = filterRisk == nil || finding.riskLevel == filterRisk
            return categoryMatch && riskMatch
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerCard

                if viewModel.isDeepScanning {
                    HStack {
                        ProgressView()
                        Text("Analyzing storage locations…")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                } else if let result = viewModel.deepScanResult {
                    filtersRow
                    findingsList(result: result)
                } else {
                    ContentUnavailableView(
                        "No deep scan yet",
                        systemImage: "magnifyingglass",
                        description: Text("Run a deep scan to find caches, simulators, and app data beyond dev-only paths.")
                    )
                    Button("Run Deep Scan") {
                        Task { await viewModel.runDeepScan() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
        }
        .navigationTitle("Storage Findings")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await viewModel.runDeepScan() }
                } label: {
                    Label("Deep Scan", systemImage: "scope")
                }
                .disabled(viewModel.isDeepScanning || viewModel.isScanning)
            }
        }
        .onChange(of: viewModel.deepScanResult?.scannedAt) { rebuildFindings() }
        .onChange(of: filterCategory) { rebuildFindings() }
        .onChange(of: filterRisk) { rebuildFindings() }
        .onAppear { rebuildFindings() }
    }

    @ViewBuilder
    private var headerCard: some View {
        if let result = viewModel.deepScanResult {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Deep Storage Analysis", systemImage: "externaldrive.badge.exclamationmark")
                        .font(.headline)
                    Spacer()
                    Text(result.scannedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("\(result.findings.count) locations · \(result.formattedFreeSpace) free")
                    .foregroundStyle(.secondary)
                if result.isCriticallyLowOnSpace {
                    Label("Low disk space — prioritize Safe cleanup targets", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.subheadline.weight(.medium))
                }
                let reclaimable = result.findings
                    .filter { $0.riskLevel == .safe && $0.cleanupTargetId != nil }
                    .map(\.size)
                    .reduce(0, +)
                if reclaimable > 0 {
                    Text("Estimated reclaimable (safe targets): \(DiskUsageModel.formatBytes(reclaimable))")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var filtersRow: some View {
        HStack(spacing: 12) {
            Picker("Category", selection: $filterCategory) {
                Text("All").tag(Optional<StorageFindingCategory>.none)
                ForEach(StorageFindingCategory.allCases) { cat in
                    Text(cat.rawValue).tag(Optional(cat))
                }
            }
            .frame(maxWidth: 220)

            Picker("Risk", selection: $filterRisk) {
                Text("All").tag(Optional<StorageRiskLevel>.none)
                Text("Safe").tag(Optional(StorageRiskLevel.safe))
                Text("Caution").tag(Optional(StorageRiskLevel.caution))
                Text("Dangerous").tag(Optional(StorageRiskLevel.dangerous))
            }
            .frame(maxWidth: 160)
        }
    }

    private func findingsList(result: DeepScanResult) -> some View {
        LazyVStack(spacing: 10) {
            if cachedFindings.isEmpty {
                Text("No findings match filters.")
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(cachedFindings.enumerated()), id: \.element.id) { index, finding in
                findingRow(rank: index + 1, finding: finding)
            }
        }
    }

    private func findingRow(rank: Int, finding: StorageFinding) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text("#\(rank)")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .frame(width: 28, alignment: .leading)

                Image(systemName: finding.category.iconName)
                    .foregroundStyle(finding.category == .appSupport ? .purple : .accentColor)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 4) {
                    Text(finding.displayName)
                        .font(.headline)
                    Text(finding.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(finding.formattedSize)
                        .font(.body.bold().monospacedDigit())
                    Text(finding.riskLevel.rawValue)
                        .font(.caption2.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(finding.riskLevel.color.opacity(0.2), in: Capsule())
                        .foregroundStyle(finding.riskLevel.color)
                }
            }

            Text(finding.growthReason)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Label(finding.suggestedAction, systemImage: "lightbulb")
                    .font(.caption)
                Spacer()
                Text(finding.cleanupFrequency)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if let targetId = finding.cleanupTargetId,
               let target = DeveloperCleanupTarget.target(forId: targetId),
               finding.riskLevel != .dangerous {
                Button("Clean in Developer Cleanup") {
                    viewModel.selectedSection = .developerCleanup
                    viewModel.requestCleanup(for: target)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
