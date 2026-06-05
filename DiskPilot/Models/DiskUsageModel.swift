//
//  DiskUsageModel.swift
//  DiskPilot
//

import Foundation
import SwiftUI

enum StorageCategory: String, CaseIterable, Identifiable {
    case system = "System"
    case developer = "Developer"
    case apps = "Apps"
    case media = "Media"
    case cache = "Cache"
    case downloads = "Downloads"
    case documents = "Documents"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .system: .red
        case .developer: .orange
        case .apps: .purple
        case .media: .pink
        case .cache: .yellow
        case .downloads: .blue
        case .documents: .green
        }
    }

    var iconName: String {
        switch self {
        case .system: "gearshape.2"
        case .developer: "chevron.left.forwardslash.chevron.right"
        case .apps: "app"
        case .media: "photo.on.rectangle"
        case .cache: "externaldrive.badge.timemachine"
        case .downloads: "arrow.down.circle"
        case .documents: "doc.text"
        }
    }
}

struct DirectoryInfo: Identifiable {
    var id: String { path }
    var path: String
    var size: UInt64
    var category: StorageCategory

    var displayName: String {
        (path as NSString).lastPathComponent
    }
}

struct DiskUsageModel {
    var totalCapacity: UInt64
    var usedSpace: UInt64
    var freeSpace: UInt64
    var categoryBreakdown: [(category: StorageCategory, size: UInt64)] = []
    var topDirectories: [DirectoryInfo] = []

    var percentageUsed: Double {
        guard totalCapacity > 0 else { return 0 }
        return Double(usedSpace) / Double(totalCapacity) * 100
    }

    var percentageFree: Double {
        guard totalCapacity > 0 else { return 0 }
        return Double(freeSpace) / Double(totalCapacity) * 100
    }

    static func formatBytes(_ bytes: UInt64) -> String {
        guard bytes > 0 else { return "0 B" }
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var index = 0
        while value >= 1024, index < units.count - 1 {
            value /= 1024
            index += 1
        }
        return String(format: "%.1f %@", value, units[index])
    }

    var formattedFreeSpace: String { Self.formatBytes(freeSpace) }
    var formattedUsedSpace: String { Self.formatBytes(usedSpace) }
    var formattedTotalCapacity: String { Self.formatBytes(totalCapacity) }
}

enum DiskHealthStatus: Equatable {
    case healthy
    case moderate
    case critical

    var color: Color {
        switch self {
        case .healthy: .green
        case .moderate: .yellow
        case .critical: .red
        }
    }

    static func fromFreePercentage(_ freePercentage: Double) -> Self {
        if freePercentage > 20 { return .healthy }
        if freePercentage > 10 { return .moderate }
        return .critical
    }
}

struct CleanupLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let action: String
    let path: String
    let bytesReclaimed: UInt64
    let success: Bool
}
