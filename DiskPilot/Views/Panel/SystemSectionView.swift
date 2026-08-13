//
//  SystemSectionView.swift
//  DiskPilot
//

import SwiftUI

/// Live CPU, memory and network, sampled once a second while the panel is open.
struct SystemSectionView: View {
    @Environment(DiskPilotViewModel.self) private var viewModel

    private var metrics: SystemMetrics { viewModel.metrics }

    var body: some View {
        PanelCard(section: .system) {
            Text("\(Int(metrics.cpuUsed.rounded()))%")
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(load(metrics.cpuUsed))
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                cpu
                memory
                network
                footer
            }
        }
    }

    private var cpu: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("CPU")
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                // User vs system split says *what kind* of busy: a pegged system
                // figure usually means I/O or a driver, not a runaway app.
                Text("\(Int(metrics.cpuUser.rounded()))% user · \(Int(metrics.cpuSystem.rounded()))% sys")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            CapacityBar(
                total: 100,
                segments: [
                    .init(id: "user", bytes: UInt64(metrics.cpuUser.rounded()), color: .blue),
                    .init(id: "system", bytes: UInt64(metrics.cpuSystem.rounded()), color: .orange),
                ],
                height: 6
            )
        }
    }

    private var memory: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Memory")
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                Text(metrics.pressure.label)
                    .font(.system(size: 9, weight: .medium))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(pressureColor.opacity(0.18), in: .capsule)
                    .foregroundStyle(pressureColor)
                Text(ByteFormat.string(metrics.memoryUsed))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            CapacityBar(
                total: metrics.memoryTotal,
                segments: [
                    .init(id: "app", bytes: metrics.memoryApp, color: .blue),
                    .init(id: "wired", bytes: metrics.memoryWired, color: .purple),
                    .init(id: "compressed", bytes: metrics.memoryCompressed, color: .orange),
                ],
                height: 6
            )
            HStack(spacing: 10) {
                legend("App", .blue, metrics.memoryApp)
                legend("Wired", .purple, metrics.memoryWired)
                legend("Compressed", .orange, metrics.memoryCompressed)
            }
        }
    }

    private var network: some View {
        HStack(spacing: 14) {
            Label {
                Text(rate(metrics.networkInPerSecond))
                    .font(.system(size: 11)).monospacedDigit()
            } icon: {
                Image(systemName: "arrow.down").font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(.green)

            Label {
                Text(rate(metrics.networkOutPerSecond))
                    .font(.system(size: 11)).monospacedDigit()
            } icon: {
                Image(systemName: "arrow.up").font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(.blue)

            Spacer()

            if metrics.swapUsed > 0 {
                Text("Swap \(ByteFormat.string(metrics.swapUsed))")
                    .font(.system(size: 10))
                    .foregroundStyle(metrics.swapUsed > 2_000_000_000 ? .orange : .secondary)
                    .monospacedDigit()
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("\(metrics.coreCount) cores")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Text("· load \(String(format: "%.2f", metrics.loadAverage[0]))")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
            Spacer()
            Text("up \(metrics.formattedUptime)")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    private func legend(_ title: String, _ color: Color, _ bytes: UInt64) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(title)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .help("\(title): \(ByteFormat.string(bytes))")
    }

    private var pressureColor: Color {
        switch metrics.pressure {
        case .normal: .green
        case .warning: .orange
        case .critical: .red
        }
    }

    private func load(_ percentage: Double) -> Color {
        if percentage > 85 { return .red }
        if percentage > 60 { return .orange }
        return .primary
    }

    private func rate(_ bytesPerSecond: UInt64) -> String {
        bytesPerSecond == 0 ? "—" : "\(ByteFormat.string(bytesPerSecond))/s"
    }
}
