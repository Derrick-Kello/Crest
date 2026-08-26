//
//  NetworkSectionView.swift
//  Crest
//

import AppKit
import SwiftUI

/// Live throughput, what this session has moved, and which apps are responsible.
///
/// The two rates get a shared sparkline rather than two separate ones: what a
/// person actually reads here is the shape of the traffic and which direction is
/// carrying it, and one chart on a shared scale answers both at a glance.
struct NetworkSectionView: View {
    @Environment(CrestViewModel.self) private var viewModel

    private var network: NetworkService { viewModel.network }
    private var reading: NetworkReading { network.reading }

    var body: some View {
        PanelCard(section: .network) {
            if reading.hasRate {
                HStack(spacing: 6) {
                    rateChip(symbol: "arrow.down", value: reading.downloadPerSecond, tint: .blue)
                    rateChip(symbol: "arrow.up", value: reading.uploadPerSecond, tint: .green)
                }
            } else {
                Text("Measuring")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                chart
                sessionRow
                Divider().padding(.vertical, 1)
                interfaceList
                Divider().padding(.vertical, 1)
                appList
            }
        }
        .onAppear { network.setActive(true) }
        .onDisappear { network.setActive(false) }
    }

    private func rateChip(symbol: String, value: UInt64, tint: Color) -> some View {
        HStack(spacing: 2) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
            Text(RateFormat.perSecond(value))
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
        }
        .foregroundStyle(tint)
    }

    // MARK: - Chart

    private var chart: some View {
        // A fixed floor keeps an idle connection from turning sensor noise into a
        // dramatic mountain range: below 64 KB/s the chart stays visibly flat.
        let scale = max(reading.peak, 64_000)

        return ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 6)
                .fill(.quaternary.opacity(0.3))

            Sparkline(values: reading.downloadHistory, maximum: scale)
                .fill(.blue.opacity(0.28))
            Sparkline(values: reading.downloadHistory, maximum: scale, strokeOnly: true)
                .stroke(.blue, lineWidth: 1)

            Sparkline(values: reading.uploadHistory, maximum: scale, strokeOnly: true)
                .stroke(.green, lineWidth: 1)
        }
        .frame(height: 46)
        .clipShape(.rect(cornerRadius: 6))
        .accessibilityLabel("Network activity over the last minute")
        .accessibilityValue("Down \(RateFormat.perSecond(reading.downloadPerSecond)), up \(RateFormat.perSecond(reading.uploadPerSecond))")
    }

    private var sessionRow: some View {
        HStack(spacing: 10) {
            Text("This session")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Label(RateFormat.string(reading.sessionDownload), systemImage: "arrow.down")
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(.blue)
            Label(RateFormat.string(reading.sessionUpload), systemImage: "arrow.up")
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(.green)
        }
        .labelStyle(.titleAndIcon)
    }

    // MARK: - Interfaces

    @ViewBuilder
    private var interfaceList: some View {
        ForEach(network.interfaces.prefix(3)) { interface in
            PanelRow(
                title: interface.displayName,
                subtitle: interface.ipv4 ?? interface.name,
                iconName: Self.symbol(for: interface),
                iconColor: interface.isUp ? .accentColor : .secondary
            ) {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(RateFormat.string(interface.bytesIn))
                        .font(.system(size: 9))
                        .monospacedDigit()
                        .foregroundStyle(.blue)
                    Text(RateFormat.string(interface.bytesOut))
                        .font(.system(size: 9))
                        .monospacedDigit()
                        .foregroundStyle(.green)
                }
            }
        }

        if network.interfaces.isEmpty {
            Text("No active network interface.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        } else {
            // Without this the per-interface figures read as session totals, since
            // the session row sits directly above them.
            Text("Interface totals are counted since the Mac started.")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
    }

    /// Icons come from the localized name rather than the BSD name, because
    /// "en0" is Wi-Fi on a laptop and Ethernet on a Mac mini.
    private static func symbol(for interface: NetworkInterfaceInfo) -> String {
        let name = interface.displayName.lowercased()
        if name.contains("wi-fi") || name.contains("wifi") || name.contains("airport") { return "wifi" }
        if name.contains("ethernet") || name.contains("lan") { return "cable.connector" }
        if name.contains("thunderbolt") { return "bolt.horizontal" }
        if name.contains("iphone") || name.contains("usb") { return "iphone" }
        return "network"
    }

    // MARK: - Apps

    @ViewBuilder
    private var appList: some View {
        HStack(spacing: 6) {
            Text("Apps using network")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            if network.isSamplingApps { ProgressView().controlSize(.mini) }
            Spacer()
        }

        if network.apps.isEmpty {
            Text(network.hasAppSample ? "No apps using the network right now." : "Measuring app traffic…")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        } else {
            ForEach(network.apps.prefix(5)) { app in
                appRow(app)
            }
        }
    }

    private func appRow(_ app: NetworkAppUsage) -> some View {
        HStack(spacing: 8) {
            if let path = app.bundlePath {
                Image(nsImage: viewModel.commandBar.icon(forApp: path))
                    .resizable()
                    .frame(width: 15, height: 15)
            } else {
                Image(systemName: "terminal")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
            }

            Text(app.name)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 6)

            Text(RateFormat.string(app.bytesIn))
                .font(.system(size: 10))
                .monospacedDigit()
                .foregroundStyle(.blue)
            Text(RateFormat.string(app.bytesOut))
                .font(.system(size: 10))
                .monospacedDigit()
                .foregroundStyle(.green)
        }
    }
}

/// A filled or stroked line through a series of samples, newest on the right.
///
/// Drawn as a `Shape` rather than a Swift Charts view because this redraws every
/// second inside a menu-bar panel: a path over sixty points costs nothing, while
/// a chart view rebuilds axes, scales and accessibility elements each tick.
struct Sparkline: Shape {
    let values: [Double]
    let maximum: Double
    var strokeOnly = false

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard values.count > 1, maximum > 0 else { return path }

        let step = rect.width / CGFloat(max(values.count - 1, 1))
        // The series is drawn right-aligned so a partly filled history grows from
        // the right edge, the way every other live graph on the Mac behaves.
        let offset = rect.width - step * CGFloat(values.count - 1)

        func point(_ index: Int) -> CGPoint {
            let fraction = min(values[index] / maximum, 1)
            return CGPoint(
                x: offset + step * CGFloat(index),
                y: rect.maxY - rect.height * CGFloat(fraction)
            )
        }

        // Built point by point rather than with `addLines`, which starts its own
        // subpath and would leave the fill's baseline corner disconnected.
        if strokeOnly {
            path.move(to: point(0))
        } else {
            path.move(to: CGPoint(x: offset, y: rect.maxY))
            path.addLine(to: point(0))
        }
        for index in 1..<values.count {
            path.addLine(to: point(index))
        }
        if !strokeOnly {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }
}
