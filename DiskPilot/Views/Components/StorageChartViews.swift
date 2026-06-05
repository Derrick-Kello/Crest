//
//  StorageChartViews.swift
//  DiskPilot
//

import SwiftUI
import Charts

struct CategoryPieChart: View {
    let breakdown: [(category: StorageCategory, size: UInt64)]

    var body: some View {
        Chart(breakdown, id: \.category) { item in
            SectorMark(
                angle: .value("Size", Double(item.size)),
                innerRadius: .ratio(0.55),
                angularInset: 1.5
            )
            .foregroundStyle(item.category.color)
            .cornerRadius(4)
        }
        .chartLegend(position: .bottom, alignment: .center)
    }
}

struct TopFoldersBarChart: View {
    let directories: [DirectoryInfo]
    let limit: Int

    private var topItems: [DirectoryInfo] {
        Array(directories.prefix(limit))
    }

    var body: some View {
        Chart(topItems) { item in
            BarMark(
                x: .value("Size", Double(item.size)),
                y: .value("Folder", item.displayName)
            )
            .foregroundStyle(item.category.color.gradient)
            .cornerRadius(4)
        }
        .chartXAxis {
            AxisMarks { value in
                if let bytes = value.as(Double.self) {
                    AxisValueLabel {
                        Text(DiskUsageModel.formatBytes(UInt64(bytes)))
                            .font(.caption2)
                    }
                }
            }
        }
    }
}

struct DiskUsageProgressRing: View {
    let percentageUsed: Double
    let health: DiskHealthStatus

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: 14)
            Circle()
                .trim(from: 0, to: min(percentageUsed / 100, 1))
                .stroke(health.color.gradient, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.6), value: percentageUsed)
            VStack(spacing: 2) {
                Text("\(Int(percentageUsed))%")
                    .font(.title.bold())
                Text("Used")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 140, height: 140)
    }
}
