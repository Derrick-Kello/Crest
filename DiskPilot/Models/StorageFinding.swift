//
//  StorageFinding.swift
//  DiskPilot
//

import Foundation
import SwiftUI

enum StorageFindingCategory: String, CaseIterable, Identifiable {
    case xcode = "Xcode & Swift"
    case node = "Node.js"
    case docker = "Docker"
    case simulator = "Simulator"
    case systemCache = "System Cache"
    case appSupport = "Application Support"
    case logs = "Logs"
    case downloads = "Downloads"
    case media = "Media"
    case git = "Git"
    case other = "Other"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .xcode: "hammer"
        case .node: "chevron.left.forwardslash.chevron.right"
        case .docker: "shippingbox"
        case .simulator: "iphone"
        case .systemCache: "externaldrive.badge.timemachine"
        case .appSupport: "app.badge"
        case .logs: "doc.text"
        case .downloads: "arrow.down.circle"
        case .media: "photo"
        case .git: "arrow.triangle.branch"
        case .other: "folder"
        }
    }
}

enum StorageRiskLevel: String, Comparable, Hashable {
    case safe = "Safe"
    case caution = "Caution"
    case dangerous = "Dangerous"

    var color: Color {
        switch self {
        case .safe: .green
        case .caution: .orange
        case .dangerous: .red
        }
    }

    private var sortOrder: Int {
        switch self {
        case .safe: 0
        case .caution: 1
        case .dangerous: 2
        }
    }

    static func < (lhs: StorageRiskLevel, rhs: StorageRiskLevel) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}

struct StorageFinding: Identifiable, Hashable {
    let id: String
    let path: String
    let displayName: String
    let size: UInt64
    let category: StorageFindingCategory
    let riskLevel: StorageRiskLevel
    let growthReason: String
    let suggestedAction: String
    let cleanupFrequency: String
    let cleanupTargetId: String?

    var formattedSize: String {
        DiskUsageModel.formatBytes(size)
    }

    var exists: Bool {
        size > 0
    }
}

struct DeepScanResult {
    let findings: [StorageFinding]
    let scannedAt: Date
    let freeSpaceBytes: UInt64
    let totalCapacityBytes: UInt64

    var isCriticallyLowOnSpace: Bool {
        guard totalCapacityBytes > 0 else { return false }
        let freeRatio = Double(freeSpaceBytes) / Double(totalCapacityBytes)
        return freeRatio < 0.05
    }

    var formattedFreeSpace: String {
        DiskUsageModel.formatBytes(freeSpaceBytes)
    }
}
