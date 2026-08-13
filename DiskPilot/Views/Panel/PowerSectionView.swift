//
//  PowerSectionView.swift
//  DiskPilot
//

import SwiftUI

/// Battery analytics: charge, health, cycles, draw, and adapter.
struct PowerSectionView: View {
    @Environment(DiskPilotViewModel.self) private var viewModel

    private var power: PowerInfo { viewModel.power }

    var body: some View {
        PanelCard(section: .power) {
            if power.hasBattery {
                HStack(spacing: 4) {
                    Image(systemName: batterySymbol)
                        .font(.system(size: 11))
                        .foregroundStyle(chargeColor)
                    Text("\(power.percentage)%")
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(chargeColor)
                }
            }
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                if power.hasBattery {
                    charge
                    Divider().padding(.vertical, 1)
                    analytics
                } else {
                    Text("This Mac has no internal battery.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var charge: some View {
        VStack(alignment: .leading, spacing: 6) {
            CapacityBar(
                total: 100,
                segments: [.init(id: "charge", bytes: UInt64(power.percentage), color: chargeColor)],
                height: 6
            )
            HStack(spacing: 4) {
                Text(power.statusDescription)
                    .font(.system(size: 11, weight: .medium))
                if let remaining = power.timeRemainingDescription {
                    Text("· \(remaining) \(power.isCharging ? "to full" : "left")")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let watts = power.watts, watts > 0.1 {
                    Text(String(format: "%.1f W", watts))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }

    private var analytics: some View {
        VStack(spacing: 5) {
            if let health = power.healthPercentage {
                PanelRow(title: "Capacity vs new", iconName: "heart") {
                    HStack(spacing: 5) {
                        // Apple treats below 80% as "Service Recommended", so that
                        // is where the colour changes rather than at an invented mark.
                        Text("\(health)%")
                            .font(.system(size: 11, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(health < 80 ? .orange : .primary)
                        if let condition = power.condition, condition != "Good" {
                            Text(condition)
                                .font(.system(size: 9))
                                .foregroundStyle(.orange)
                        }
                    }
                }
                .help("Full-charge capacity as a share of this battery's original design capacity. System Settings smooths its own figure, so expect a few points of difference.")
            }

            if let cycles = power.cycleCount {
                PanelRow(title: "Cycle count", iconName: "arrow.triangle.2.circlepath") {
                    Text("\(cycles)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            if let max = power.maxCapacity, let design = power.designCapacity {
                PanelRow(title: "Capacity", iconName: "battery.100") {
                    Text("\(max) / \(design) mAh")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            if let temperature = power.temperatureCelsius, temperature > 0 {
                PanelRow(title: "Temperature", iconName: "thermometer.medium") {
                    Text(String(format: "%.1f °C", temperature))
                        .font(.system(size: 11))
                        .foregroundStyle(temperature > 40 ? .orange : .secondary)
                        .monospacedDigit()
                }
            }

            if let adapter = power.adapterWatts {
                PanelRow(title: "Adapter", iconName: "powerplug") {
                    Text("\(adapter) W")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }

    private var chargeColor: Color {
        if power.isCharging { return .green }
        if power.percentage <= 10 { return .red }
        if power.percentage <= 20 { return .orange }
        return .primary
    }

    private var batterySymbol: String {
        if power.isCharging { return "battery.100.bolt" }
        switch power.percentage {
        case ..<13: return "battery.0"
        case ..<38: return "battery.25"
        case ..<63: return "battery.50"
        case ..<88: return "battery.75"
        default: return "battery.100"
        }
    }
}
