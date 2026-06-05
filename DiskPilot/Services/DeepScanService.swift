//
//  DeepScanService.swift
//  DiskPilot
//

import Foundation
import OSLog

/// Catalog of storage locations from addups.md — scans only user-writable home paths.
final class DeepScanService: Sendable {
    static let shared = DeepScanService()

    private let logger = Logger(subsystem: "com.diskpilot", category: "DeepScan")
    private let diskService = DiskService.shared
    private let fileManager = FileManager.default

    struct ScanTarget {
        let id: String
        let relativePath: String
        let displayName: String
        let category: StorageFindingCategory
        let growthReason: String
        let suggestedAction: String
        let cleanupFrequency: String
        let cleanupTargetId: String?
    }

    private let targets: [ScanTarget] = [
        // Xcode & Swift
        ScanTarget(id: "xcode-derived", relativePath: "Library/Developer/Xcode/DerivedData",
                   displayName: "Xcode DerivedData", category: .xcode,
                   growthReason: "Rebuilds on every Xcode compile",
                   suggestedAction: "Delete folder contents; Xcode recreates on next build",
                   cleanupFrequency: "Weekly", cleanupTargetId: "xcode-derived"),
        ScanTarget(id: "xcode-archives", relativePath: "Library/Developer/Xcode/Archives",
                   displayName: "Xcode Archives", category: .xcode,
                   growthReason: "IPA/archive exports accumulate",
                   suggestedAction: "Remove old archives you no longer need",
                   cleanupFrequency: "Monthly", cleanupTargetId: nil),
        ScanTarget(id: "xcode-devicesupport", relativePath: "Library/Developer/Xcode/iOS DeviceSupport",
                   displayName: "iOS DeviceSupport", category: .xcode,
                   growthReason: "Symbol files per iOS version after device connect",
                   suggestedAction: "Delete versions you no longer debug against",
                   cleanupFrequency: "Quarterly", cleanupTargetId: nil),
        ScanTarget(id: "xcode-cache", relativePath: "Library/Caches/com.apple.dt.Xcode",
                   displayName: "Xcode Caches", category: .xcode,
                   growthReason: "IDE indexing and tooling cache",
                   suggestedAction: "Safe to clear; may slow first reopen",
                   cleanupFrequency: "Monthly", cleanupTargetId: "xcode-cache"),
        ScanTarget(id: "swiftpm-cache", relativePath: "Library/Caches/org.swift.swiftpm",
                   displayName: "Swift Package Manager Cache", category: .xcode,
                   growthReason: "SPM dependency downloads",
                   suggestedAction: "Delete; packages re-fetch on resolve",
                   cleanupFrequency: "Monthly", cleanupTargetId: "swiftpm-cache"),

        // Simulator
        ScanTarget(id: "core-simulator", relativePath: "Library/Developer/CoreSimulator",
                   displayName: "iOS Simulator Data", category: .simulator,
                   growthReason: "App data, media, and unavailable device images",
                   suggestedAction: "Run simctl delete unavailable; wipe unused devices",
                   cleanupFrequency: "Monthly", cleanupTargetId: "ios-simulator"),

        // Node
        ScanTarget(id: "npm-cache", relativePath: ".npm",
                   displayName: "npm Cache", category: .node,
                   growthReason: "Package tarball cache",
                   suggestedAction: "npm cache clean --force",
                   cleanupFrequency: "Weekly", cleanupTargetId: "npm-cache"),
        ScanTarget(id: "yarn-cache", relativePath: "Library/Caches/Yarn",
                   displayName: "Yarn Cache", category: .node,
                   growthReason: "Yarn global cache grows with installs",
                   suggestedAction: "yarn cache clean or delete cache folder",
                   cleanupFrequency: "Weekly", cleanupTargetId: "yarn-cache"),
        ScanTarget(id: "pnpm-store", relativePath: "Library/pnpm/store",
                   displayName: "pnpm Store", category: .node,
                   growthReason: "Content-addressable package store",
                   suggestedAction: "pnpm store prune",
                   cleanupFrequency: "Monthly", cleanupTargetId: nil),
        ScanTarget(id: "vite-cache", relativePath: "Library/Caches/vite",
                   displayName: "Vite Cache", category: .node,
                   growthReason: "Dev server dependency pre-bundling",
                   suggestedAction: "Delete cache folder",
                   cleanupFrequency: "Weekly", cleanupTargetId: nil),
        ScanTarget(id: "turbo-cache", relativePath: "Library/Caches/turbo",
                   displayName: "Turborepo Cache", category: .node,
                   growthReason: "Monorepo build cache",
                   suggestedAction: "Delete or turbo prune",
                   cleanupFrequency: "Monthly", cleanupTargetId: nil),

        // Docker
        ScanTarget(id: "docker-data", relativePath: ".docker",
                   displayName: "Docker Local Data", category: .docker,
                   growthReason: "Images, layers, and volumes",
                   suggestedAction: "docker system prune; review volumes",
                   cleanupFrequency: "Monthly", cleanupTargetId: nil),

        // System caches (non-OS-critical)
        ScanTarget(id: "user-caches", relativePath: "Library/Caches",
                   displayName: "User Caches (total)", category: .systemCache,
                   growthReason: "Apps regenerate browser, editor, and tool caches",
                   suggestedAction: "Clear per-app safe caches below",
                   cleanupFrequency: "Weekly", cleanupTargetId: nil),
        ScanTarget(id: "shipit-vscode", relativePath: "Library/Caches/com.microsoft.VSCode.ShipIt",
                   displayName: "VS Code Updater Cache", category: .systemCache,
                   growthReason: "Auto-update staging files",
                   suggestedAction: "Delete ShipIt folder",
                   cleanupFrequency: "After updates", cleanupTargetId: "shipit-vscode"),
        ScanTarget(id: "homebrew-cache", relativePath: "Library/Caches/Homebrew",
                   displayName: "Homebrew Cache", category: .systemCache,
                   growthReason: "Downloaded bottles",
                   suggestedAction: "brew cleanup -s",
                   cleanupFrequency: "Monthly", cleanupTargetId: "homebrew-cache"),
        ScanTarget(id: "pip-cache", relativePath: "Library/Caches/pip",
                   displayName: "pip Cache", category: .systemCache,
                   growthReason: "Python wheel cache",
                   suggestedAction: "pip cache purge",
                   cleanupFrequency: "Monthly", cleanupTargetId: "python-cache"),

        // Gradle / Android
        ScanTarget(id: "gradle-cache", relativePath: ".gradle/caches",
                   displayName: "Gradle Cache", category: .xcode,
                   growthReason: "Android/Java dependency cache",
                   suggestedAction: "Delete caches folder",
                   cleanupFrequency: "Monthly", cleanupTargetId: "gradle-cache"),
        ScanTarget(id: "android-avd", relativePath: ".android/avd",
                   displayName: "Android Emulator AVDs", category: .simulator,
                   growthReason: "Virtual device disk images",
                   suggestedAction: "Remove unused AVDs in Android Studio",
                   cleanupFrequency: "Quarterly", cleanupTargetId: nil),

        // Logs & downloads
        ScanTarget(id: "user-logs", relativePath: "Library/Logs",
                   displayName: "User Logs", category: .logs,
                   growthReason: "App and system logs accumulate",
                   suggestedAction: "Delete old logs; apps recreate as needed",
                   cleanupFrequency: "Weekly", cleanupTargetId: "user-logs"),
        ScanTarget(id: "downloads", relativePath: "Downloads",
                   displayName: "Downloads", category: .downloads,
                   growthReason: "Manual and browser downloads",
                   suggestedAction: "Review and delete manually — never auto-delete",
                   cleanupFrequency: "Weekly", cleanupTargetId: nil),

        // App support (aggregate + common dev apps)
        ScanTarget(id: "app-support-total", relativePath: "Library/Application Support",
                   displayName: "Application Support (total)", category: .appSupport,
                   growthReason: "App databases, extensions, local data",
                   suggestedAction: "Inspect largest children; remove unused app data only",
                   cleanupFrequency: "Quarterly", cleanupTargetId: nil),

        // Trash
        ScanTarget(id: "trash", relativePath: ".Trash",
                   displayName: "Trash", category: .other,
                   growthReason: "Deleted files awaiting empty trash",
                   suggestedAction: "Empty Trash in Finder",
                   cleanupFrequency: "Daily", cleanupTargetId: "empty-trash"),
    ]

    func runDeepScan() async -> DeepScanResult {
        logger.debug("Starting deep scan")
        let home = fileManager.homeDirectoryForCurrentUser.path
        let volume = try? volumeStats()

        var findings: [StorageFinding] = []

        // All scan tasks run concurrently inside the task group.
        // Each task does a pure-Swift directory walk (no subprocesses).
        await withTaskGroup(of: [StorageFinding].self) { group in
            for target in targets {
                group.addTask { [self] in
                    if let one = self.scanTarget(target, home: home) {
                        return [one]
                    }
                    return []
                }
            }
            group.addTask { [self] in
                self.scanCacheChildren(home: home)
            }
            group.addTask { [self] in
                self.scanAppSupportChildren(home: home)
            }

            for await batch in group {
                findings.append(contentsOf: batch)
            }
        }

        findings.sort { $0.size > $1.size }

        let result = DeepScanResult(
            findings: findings,
            scannedAt: Date(),
            freeSpaceBytes: volume?.free ?? 0,
            totalCapacityBytes: volume?.total ?? 0
        )
        logger.debug("Deep scan complete: \(findings.count) findings")
        return result
    }

    // MARK: - Private

    private struct VolumeStats {
        let total: UInt64
        let free: UInt64
    }

    private func volumeStats() throws -> VolumeStats {
        let homeURL = fileManager.homeDirectoryForCurrentUser
        let values = try homeURL.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
        ])
        return VolumeStats(
            total: UInt64(values.volumeTotalCapacity ?? 0),
            free: UInt64(values.volumeAvailableCapacity ?? 0)
        )
    }

    private func scanTarget(_ target: ScanTarget, home: String) -> StorageFinding? {
        let fullPath = (home as NSString).appendingPathComponent(target.relativePath)
        guard fileManager.fileExists(atPath: fullPath) else { return nil }

        // directorySize uses pure Swift URLResourceValues — no subprocess needed.
        let size = diskService.allocatedSize(at: URL(fileURLWithPath: fullPath))
        guard size > 0 else { return nil }

        return makeFinding(
            id: target.id,
            path: fullPath,
            displayName: target.displayName,
            size: size,
            category: target.category,
            growthReason: target.growthReason,
            suggestedAction: target.suggestedAction,
            cleanupFrequency: target.cleanupFrequency,
            cleanupTargetId: target.cleanupTargetId
        )
    }

    private func scanCacheChildren(home: String) -> [StorageFinding] {
        let cachesPath = (home as NSString).appendingPathComponent("Library/Caches")
        guard let children = try? fileManager.contentsOfDirectory(atPath: cachesPath) else { return [] }

        let skipNames: Set<String> = [
            "Yarn", "com.apple.dt.Xcode", "org.swift.swiftpm", "pip",
            "com.microsoft.VSCode.ShipIt", "Homebrew", "vite", "turbo",
        ]

        var results: [StorageFinding] = []
        for name in children {
            if skipNames.contains(name) { continue }
            if name.hasPrefix("com.apple.") && !name.contains("ShipIt") { continue }

            let fullPath = (cachesPath as NSString).appendingPathComponent(name)
            let size = diskService.allocatedSize(at: URL(fileURLWithPath: fullPath))
            guard size > 50 * 1024 * 1024 else { continue } // 50 MB+

            results.append(makeFinding(
                id: "cache-\(name)",
                path: fullPath,
                displayName: "Cache: \(name)",
                size: size,
                category: .systemCache,
                growthReason: "Application cache — regenerates on use",
                suggestedAction: "Safe to delete if you recognize the app; it will rebuild",
                cleanupFrequency: "As needed",
                cleanupTargetId: nil
            ))
        }
        return results
    }

    private func scanAppSupportChildren(home: String) -> [StorageFinding] {
        let base = (home as NSString).appendingPathComponent("Library/Application Support")
        guard let children = try? fileManager.contentsOfDirectory(atPath: base) else { return [] }

        var results: [StorageFinding] = []
        for name in children {
            let fullPath = (base as NSString).appendingPathComponent(name)
            let size = diskService.allocatedSize(at: URL(fileURLWithPath: fullPath))
            guard size > 200 * 1024 * 1024 else { continue } // 200 MB+

            results.append(makeFinding(
                id: "appsupport-\(name)",
                path: fullPath,
                displayName: "App Support: \(name)",
                size: size,
                category: .appSupport,
                growthReason: "Application local data and databases",
                suggestedAction: "Review in Finder — uninstall unused apps if large",
                cleanupFrequency: "Quarterly",
                cleanupTargetId: nil
            ))
        }
        return results
    }

    private func makeFinding(
        id: String,
        path: String,
        displayName: String,
        size: UInt64,
        category: StorageFindingCategory,
        growthReason: String,
        suggestedAction: String,
        cleanupFrequency: String,
        cleanupTargetId: String?
    ) -> StorageFinding {
        let risk = PathSafetyClassifier.riskLevel(for: path, category: category)
        return StorageFinding(
            id: id,
            path: path,
            displayName: displayName,
            size: size,
            category: category,
            riskLevel: risk,
            growthReason: growthReason,
            suggestedAction: suggestedAction,
            cleanupFrequency: cleanupFrequency,
            cleanupTargetId: cleanupTargetId
        )
    }
}
