//
//  DiskService.swift
//  DiskPilot
//

import Foundation
import OSLog

final class DiskService: Sendable {
    static let shared = DiskService()

    private let logger = Logger(subsystem: "com.diskpilot", category: "DiskService")
    private let fileManager = FileManager.default

    private let scanPaths: [String] = [
        "Library/Application Support",
        "Library/Containers",
        "Library/Group Containers",
        "Developer",
        ".npm",
        ".android",
        ".docker",
        "Downloads",
        "Library/Caches",
    ]

    func scanDisk() async throws -> DiskUsageModel {
        logger.debug("Starting disk scan")
        let volumeStats = try volumeStatistics()
        var directories = await scanDirectories()
        directories.sort { $0.size > $1.size }

        var categoryTotals: [StorageCategory: UInt64] = [:]
        for dir in directories {
            categoryTotals[dir.category, default: 0] += dir.size
        }

        let breakdown = StorageCategory.allCases.map { category in
            (category: category, size: categoryTotals[category] ?? 0)
        }.filter { $0.size > 0 }

        let model = DiskUsageModel(
            totalCapacity: volumeStats.total,
            usedSpace: volumeStats.used,
            freeSpace: volumeStats.free,
            categoryBreakdown: breakdown,
            topDirectories: Array(directories.prefix(50))
        )
        logger.debug("Scan complete — free: \(model.formattedFreeSpace)")
        return model
    }

    /// Returns the on-disk size of a path using pure Swift — no subprocess overhead.
    func directorySize(at path: String) -> UInt64 {
        let resolved = expandTilde(path)
        guard fileManager.fileExists(atPath: resolved) else { return 0 }
        return allocatedSize(at: URL(fileURLWithPath: resolved))
    }

    // MARK: - Private

    private struct VolumeStats {
        let total: UInt64
        let used: UInt64
        let free: UInt64
    }

    private func volumeStatistics() throws -> VolumeStats {
        let homeURL = fileManager.homeDirectoryForCurrentUser
        let values = try homeURL.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
        ])
        let total = UInt64(values.volumeTotalCapacity ?? 0)
        // Use the "important usage" available capacity — matches what Finder shows.
        let free = UInt64(values.volumeAvailableCapacityForImportantUsage ?? 0)
        let used = total > free ? total - free : 0
        return VolumeStats(total: total, used: used, free: free)
    }

    private func scanDirectories() async -> [DirectoryInfo] {
        let home = fileManager.homeDirectoryForCurrentUser.path

        return await withTaskGroup(of: DirectoryInfo?.self, returning: [DirectoryInfo].self) { group in
            for relative in scanPaths {
                let fullPath = (home as NSString).appendingPathComponent(relative)
                group.addTask { [self] in
                    guard self.fileManager.fileExists(atPath: fullPath) else { return nil }
                    let size = self.allocatedSize(at: URL(fileURLWithPath: fullPath))
                    guard size > 0 else { return nil }
                    return DirectoryInfo(
                        path: fullPath,
                        size: size,
                        category: self.categorize(path: fullPath)
                    )
                }
            }
            var results: [DirectoryInfo] = []
            for await item in group {
                if let item { results.append(item) }
            }
            return results
        }
    }

    /// Recursively sums `fileAllocatedSize` — reflects actual disk blocks used (matches `du`).
    /// This is a pure Swift walk with no subprocess, which is much faster for typical directories.
    func allocatedSize(at url: URL) -> UInt64 {
        // For a single regular file.
        if let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileAllocatedSizeKey]),
           values.isRegularFile == true {
            return UInt64(values.fileAllocatedSize ?? 0)
        }

        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileAllocatedSizeKey, .isSymbolicLinkKey]
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return 0 }

        var total: UInt64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: keys),
                  values.isSymbolicLink != true,
                  values.isRegularFile == true,
                  let size = values.fileAllocatedSize else { continue }
            total += UInt64(size)
        }
        return total
    }

    private func categorize(path: String) -> StorageCategory {
        let lower = path.lowercased()
        if lower.contains("/downloads") { return .downloads }
        if lower.contains("npm") || lower.contains("/.gradle")
            || lower.contains("xcode") || lower.contains("/developer/")
            || lower.contains(".android") || lower.contains(".docker") {
            return .developer
        }
        if lower.contains("/caches/") || lower.hasSuffix("/caches") { return .cache }
        if lower.contains("photos") || lower.contains("music") || lower.contains("movies") {
            return .media
        }
        if lower.contains("/applications/") || lower.contains(".app/") { return .apps }
        if lower.contains("/documents/") { return .documents }
        return .system
    }

    private func expandTilde(_ path: String) -> String {
        guard path.hasPrefix("~") else { return path }
        return fileManager.homeDirectoryForCurrentUser.path + String(path.dropFirst())
    }
}
