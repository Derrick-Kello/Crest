//
//  OverviewView.swift
//  DiskPilot
//

import SwiftUI

struct OverviewView: View {
    @Environment(DiskPilotViewModel.self) private var viewModel

    var body: some View {
        ScrollView {
            if let usage = viewModel.diskUsage {
                content(usage: usage)
            } else if viewModel.isScanning {
                ProgressView("Scanning disk…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(40)
            } else {
                ContentUnavailableView(
                    "No scan data",
                    systemImage: "externaldrive",
                    description: Text("Run a scan to see storage overview.")
                )
                .padding(40)
            }
        }
        .navigationTitle("Overview")
    }

    @ViewBuilder
    private func content(usage: DiskUsageModel) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            summaryCard(usage: usage)

            if viewModel.isCriticallyLowOnSpace {
                lowDiskBanner
            }

            if viewModel.topSafeReclaimableBytes > 0 {
                Button {
                    viewModel.selectedSection = .storageFindings
                } label: {
                    HStack {
                        Image(systemName: "scope")
                        Text("Storage Findings: up to \(DiskUsageModel.formatBytes(viewModel.topSafeReclaimableBytes)) reclaimable")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .padding(12)
                    .background(.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }

            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Storage Breakdown")
                        .font(.headline)
                    CategoryPieChart(breakdown: usage.categoryBreakdown)
                        .frame(height: 260)
                }
                .frame(maxWidth: .infinity)

                categoryLegend(usage: usage)
            }

            quickActions
        }
        .padding(24)
    }

    private func summaryCard(usage: DiskUsageModel) -> some View {
        HStack(spacing: 32) {
            DiskUsageProgressRing(
                percentageUsed: usage.percentageUsed,
                health: viewModel.healthStatus
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("Disk Summary")
                    .font(.title2.bold())
                LabeledContent("Total", value: usage.formattedTotalCapacity)
                LabeledContent("Used", value: usage.formattedUsedSpace)
                LabeledContent("Free", value: usage.formattedFreeSpace)
                if let date = viewModel.lastScanDate {
                    Text("Last scan: \(date.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func categoryLegend(usage: DiskUsageModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Categories")
                .font(.headline)
            ForEach(usage.categoryBreakdown, id: \.category) { item in
                HStack {
                    Image(systemName: item.category.iconName)
                        .foregroundStyle(item.category.color)
                        .frame(width: 20)
                    Text(item.category.rawValue)
                    Spacer()
                    Text(DiskUsageModel.formatBytes(item.size))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .frame(width: 220)
    }

    private var lowDiskBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.title2)
            VStack(alignment: .leading, spacing: 4) {
                Text("Low disk space")
                    .font(.headline)
                Text("macOS needs headroom for updates and swap. Open Storage Findings for ranked cleanup options.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Findings") {
                viewModel.selectedSection = .storageFindings
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(14)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    private var quickActions: some View {
        HStack(spacing: 12) {
            Button {
                Task { await viewModel.runScan() }
            } label: {
                Label("Run Scan", systemImage: "arrow.clockwise")
            }
            .disabled(viewModel.isScanning)

            Button {
                Task { await viewModel.quickCleanDeveloperCaches() }
            } label: {
                Label("Clean Dev Caches", systemImage: "sparkles")
            }

            Button {
                viewModel.selectedSection = .storageFindings
            } label: {
                Label("Storage Findings", systemImage: "scope")
            }

            Button {
                viewModel.selectedSection = .docker
            } label: {
                Label("Docker Manager", systemImage: "shippingbox")
            }
        }
    }
}
