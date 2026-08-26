//
//  ConcurrencyUtil.swift
//  Crest
//

import Foundation

/// Runs `transform` over `items` with at most `maxConcurrent` tasks in flight at
/// once, returning the results in completion order.
///
/// Directory walks are I/O-bound: launching 25 of them simultaneously (as the
/// deep scan did) thrashes the disk and spikes memory because every walk holds a
/// live enumerator at the same time. Capping the in-flight count keeps throughput
/// high while bounding contention and peak RAM. Marked `nonisolated` so the work
/// runs off the main actor regardless of the project's MainActor-default isolation.
nonisolated func mapConcurrently<Item: Sendable, Result: Sendable>(
    _ items: [Item],
    maxConcurrent: Int,
    _ transform: @escaping @Sendable (Item) async -> Result
) async -> [Result] {
    guard !items.isEmpty else { return [] }
    let limit = max(1, min(maxConcurrent, items.count))

    return await withTaskGroup(of: Result.self, returning: [Result].self) { group in
        var nextIndex = 0
        while nextIndex < limit {
            let item = items[nextIndex]
            group.addTask { await transform(item) }
            nextIndex += 1
        }

        var results: [Result] = []
        results.reserveCapacity(items.count)
        while let result = await group.next() {
            results.append(result)
            if nextIndex < items.count {
                let item = items[nextIndex]
                group.addTask { await transform(item) }
                nextIndex += 1
            }
        }
        return results
    }
}
