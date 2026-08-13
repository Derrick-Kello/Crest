//
//  DiskService.swift
//  DiskPilot
//

import Foundation
import OSLog

/// Volume figures and directory sizing.
///
/// The split here matters for memory: `volumeSnapshot()` is a pure `statfs`-style
/// resource-value read that touches no directories, and it is the only thing the
/// menu-bar refresh timer calls. Walking trees happens exclusively in response to
/// something the user asked for.
struct VolumeSnapshot: Sendable, Equatable {
    var totalCapacity: UInt64 = 0
    var freeSpace: UInt64 = 0

    var usedSpace: UInt64 { totalCapacity > freeSpace ? totalCapacity - freeSpace : 0 }

    var percentageUsed: Double {
        guard totalCapacity > 0 else { return 0 }
        return Double(usedSpace) / Double(totalCapacity) * 100
    }

    var percentageFree: Double {
        guard totalCapacity > 0 else { return 0 }
        return Double(freeSpace) / Double(totalCapacity) * 100
    }

    var formattedFree: String { ByteFormat.string(freeSpace) }
    var formattedUsed: String { ByteFormat.string(usedSpace) }
    var formattedTotal: String { ByteFormat.string(totalCapacity) }
}

nonisolated final class DiskService: Sendable {
    static let shared = DiskService()

    private let logger = Logger(subsystem: "com.diskpilot", category: "DiskService")
    private let fileManager = FileManager.default
    private let sizeCache = SizeCache()

    // MARK: - Volume stats

    /// Cheap enough to call on a timer: no directory is opened or walked.
    func volumeSnapshot() -> VolumeSnapshot {
        let homeURL = fileManager.homeDirectoryForCurrentUser
        guard let values = try? homeURL.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
        ]) else { return VolumeSnapshot() }

        // "Important usage" is the figure Finder shows, which includes space macOS
        // would purge on demand. Reporting anything else means our number and the
        // one in Finder disagree, and the user believes Finder.
        let total = UInt64(values.volumeTotalCapacity ?? 0)
        let free = UInt64(values.volumeAvailableCapacityForImportantUsage ?? 0)
        return VolumeSnapshot(totalCapacity: total, freeSpace: free)
    }

    // MARK: - Sizing

    func directorySize(at path: String) -> UInt64 {
        let resolved = expandTilde(path)
        guard fileManager.fileExists(atPath: resolved) else { return 0 }
        return allocatedSize(at: URL(fileURLWithPath: resolved))
    }

    /// Recursively sums `fileAllocatedSize` — actual blocks on disk, matching `du`.
    /// Results are cached briefly so overlapping scans don't re-walk the same tree.
    func allocatedSize(at url: URL) -> UInt64 {
        let key = url.path
        if let cached = sizeCache.value(for: key) { return cached }
        let size = computeAllocatedSize(at: url)
        sizeCache.store(size, for: key)
        return size
    }

    /// Drops cached sizes so the next scan reflects freed space, not stale numbers.
    func invalidateSizeCache() {
        sizeCache.invalidate()
    }

    private func computeAllocatedSize(at url: URL) -> UInt64 {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileAllocatedSizeKey, .isSymbolicLinkKey]

        if let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true {
            return UInt64(values.fileAllocatedSize ?? 0)
        }

        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return 0 }

        // The enumerator vends autoreleased URL and resource-value objects. Without
        // draining a pool, walking a tree with hundreds of thousands of files
        // (CoreSimulator, DerivedData, node_modules) pins every one of them until
        // the walk ends. Draining in batches bounds peak memory to a few thousand
        // live objects while keeping per-iteration overhead negligible.
        var total: UInt64 = 0
        var finished = false
        while !finished {
            autoreleasepool {
                for _ in 0..<8192 {
                    guard let fileURL = enumerator.nextObject() as? URL else {
                        finished = true
                        return
                    }
                    guard let values = try? fileURL.resourceValues(forKeys: keys),
                          values.isSymbolicLink != true,
                          values.isRegularFile == true,
                          let size = values.fileAllocatedSize else { continue }
                    total += UInt64(size)
                }
            }
        }
        return total
    }

    private func expandTilde(_ path: String) -> String {
        guard path.hasPrefix("~") else { return path }
        return fileManager.homeDirectoryForCurrentUser.path + String(path.dropFirst())
    }
}

/// Size cache with a hard entry cap and LRU eviction.
///
/// The previous version had a TTL but no bound and never removed anything: expired
/// entries stayed in the dictionary forever, so a long-running session accumulated
/// one entry per path ever sized — thousands of them once per-child cache and app
/// leftover scans start walking `~/Library`. The cap is what keeps this flat.
private final class SizeCache: @unchecked Sendable {
    private struct Entry {
        let size: UInt64
        let storedAt: Date
        var lastAccess: Date
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    private let ttl: TimeInterval = 45
    private let capacity = 512

    func value(for key: String) -> UInt64? {
        lock.lock(); defer { lock.unlock() }
        guard var entry = entries[key] else { return nil }
        guard Date().timeIntervalSince(entry.storedAt) < ttl else {
            entries.removeValue(forKey: key)
            return nil
        }
        entry.lastAccess = Date()
        entries[key] = entry
        return entry.size
    }

    func store(_ size: UInt64, for key: String) {
        lock.lock(); defer { lock.unlock() }
        entries[key] = Entry(size: size, storedAt: Date(), lastAccess: Date())
        guard entries.count > capacity else { return }
        evictLocked()
    }

    func invalidate() {
        lock.lock(); defer { lock.unlock() }
        entries.removeAll(keepingCapacity: false)
    }

    /// Drops expired entries first; if that isn't enough, drops the least recently
    /// used until the cache is back to three quarters of capacity, so eviction runs
    /// occasionally in bulk rather than on every single insert past the limit.
    private func evictLocked() {
        let now = Date()
        entries = entries.filter { now.timeIntervalSince($0.value.storedAt) < ttl }
        guard entries.count > capacity else { return }

        let target = capacity * 3 / 4
        let ordered = entries.sorted { $0.value.lastAccess < $1.value.lastAccess }
        for (key, _) in ordered.prefix(entries.count - target) {
            entries.removeValue(forKey: key)
        }
    }
}
