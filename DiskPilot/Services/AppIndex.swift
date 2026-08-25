//
//  AppIndex.swift
//  DiskPilot
//

import AppKit
import Foundation

struct IndexedApp: Sendable, Identifiable, Hashable {
    var id: String { path }
    let name: String
    let path: String
    /// Precomputed once at index time so scoring never lowercases in the hot loop.
    let lowercaseName: String
    /// Initials of each word — "Activity Monitor" → "am", "VS Code" → "vc".
    let initials: String
}

/// Finds every installed app and ranks them against what the user types.
///
/// Built to answer within a keystroke: the scan runs once in the background at
/// launch, and matching afterwards is pure string work over a preallocated array.
nonisolated final class AppIndex: Sendable {

    // MARK: - Discovery

    /// Walks the standard app locations, descending a few levels so vendor folders
    /// are covered. The previous version only listed the immediate children of a
    /// handful of directories, which silently missed everything filed under a
    /// vendor folder — Adobe Acrobat, the Python tools, and so on.
    static func scan() -> [IndexedApp] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let roots = [
            "/Applications",
            "/System/Applications",
            "/System/Library/CoreServices/Applications",
            // Safari and its siblings ship in a Cryptex and are only reachable
            // through a symlink in /Applications that `contentsOfDirectory` does
            // not return — so without this root, searching "safari" finds nothing.
            "/System/Cryptexes/App/System/Applications",
            "\(home)/Applications",
            "\(home)/Developer/Applications",
        ]

        // Keyed by name so an app reachable through two paths — a Cryptex and its
        // symlink, say — produces one row instead of two identical ones.
        var byName: [String: IndexedApp] = [:]
        for root in roots {
            collect(root: URL(fileURLWithPath: root), depth: 0, into: &byName)
        }
        return byName.values.sorted { $0.name < $1.name }
    }

    /// `.app` bundles are directories, so the walk must stop at one rather than
    /// descend into its Contents — hence the manual recursion instead of a deep
    /// enumerator, which would wander into every helper app inside every bundle.
    private static func collect(root: URL, depth: Int, into result: inout [String: IndexedApp]) {
        guard depth <= 3,
              let entries = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
              )
        else { return }

        for url in entries {
            if url.pathExtension == "app" {
                let name = url.deletingPathExtension().lastPathComponent
                let key = name.lowercased()
                // First root wins: /Applications before the system locations, so a
                // user-installed copy takes precedence over a bundled one.
                guard result[key] == nil else { continue }
                result[key] = IndexedApp(
                    name: name,
                    path: url.path,
                    lowercaseName: key,
                    initials: initials(of: name)
                )
                continue
            }
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDirectory {
                collect(root: url, depth: depth + 1, into: &result)
            }
        }
    }

    /// First letter of each word, plus internal capitals so "VSCodium" yields "vc"
    /// and typing "vsc" still lands on it through the substring path.
    static func initials(of name: String) -> String {
        var result = ""
        var previousWasBoundary = true
        var previousWasLower = false

        for character in name {
            if character == " " || character == "-" || character == "_" || character == "." {
                previousWasBoundary = true
                previousWasLower = false
                continue
            }
            if previousWasBoundary || (character.isUppercase && previousWasLower) {
                result.append(Character(character.lowercased()))
            }
            previousWasLower = character.isLowercase || character.isNumber
            previousWasBoundary = false
        }
        return result
    }

    // MARK: - Ranking

    /// Scores `candidate` against `query`, both lowercased, or nil for no match.
    ///
    /// Ordered the way a launcher is expected to behave: an exact name beats a
    /// prefix, a prefix beats initials, initials beat a substring, and a scattered
    /// subsequence comes last. Without the initials tier, "am" would rank a dozen
    /// apps containing an "a…m" somewhere above Activity Monitor.
    static func score(query: String, candidate: String, initials: String) -> Int? {
        guard !query.isEmpty else { return 0 }

        if candidate == query { return 12_000 }
        if candidate.hasPrefix(query) { return 10_000 - min(candidate.count, 60) }
        if initials == query { return 9_000 }
        if initials.hasPrefix(query) { return 8_000 - min(initials.count, 40) }

        // A word inside the name starting with the query: "code" → "Visual Studio Code".
        if let wordScore = wordPrefixScore(query: query, candidate: candidate) {
            return wordScore
        }

        if let range = candidate.range(of: query) {
            let offset = candidate.distance(from: candidate.startIndex, to: range.lowerBound)
            return 5_000 - min(offset * 10, 1_000)
        }

        return subsequenceScore(query: query, candidate: candidate)
    }

    private static func wordPrefixScore(query: String, candidate: String) -> Int? {
        var best: Int?
        var index = candidate.startIndex
        var wordNumber = 0

        while index < candidate.endIndex {
            // Step to the start of the next word.
            if index != candidate.startIndex {
                let previous = candidate[candidate.index(before: index)]
                guard previous == " " || previous == "-" || previous == "_" else {
                    index = candidate.index(after: index)
                    continue
                }
                wordNumber += 1
            }
            if candidate[index...].hasPrefix(query) {
                let score = 7_000 - min(wordNumber * 100, 900)
                best = max(best ?? 0, score)
            }
            index = candidate.index(after: index)
        }
        return best
    }

    /// Every query character appears in order. Consecutive runs and word starts
    /// score higher, so "actmon" ranks Activity Monitor well while a coincidental
    /// scattering of the same letters scores near the floor.
    private static func subsequenceScore(query: String, candidate: String) -> Int? {
        var score = 0
        var streak = 0
        var index = candidate.startIndex
        var previousWasBoundary = true

        for character in query {
            var matched = false
            while index < candidate.endIndex {
                let current = candidate[index]
                index = candidate.index(after: index)
                if current == character {
                    streak += 1
                    score += 12 + streak * 3 + (previousWasBoundary ? 20 : 0)
                    previousWasBoundary = false
                    matched = true
                    break
                }
                streak = 0
                previousWasBoundary = current == " " || current == "-" || current == "_"
            }
            guard matched else { return nil }
        }
        // Shorter names win ties: "Mail" over "Mailbox Assistant" for "mail".
        return 2_000 + score - min(candidate.count, 40)
    }
}

/// Launch history, so the apps you actually open float to the top.
///
/// Frequency alone entrenches whatever you opened most last month; recency alone
/// forgets your daily tools. Combining them — the usual "frecency" — keeps the
/// ranking responsive without thrashing.
struct LaunchHistory: Codable, Sendable {
    private var counts: [String: Int] = [:]
    private var lastUsed: [String: Date] = [:]

    mutating func record(_ id: String) {
        counts[id, default: 0] += 1
        lastUsed[id] = Date()
    }

    func boost(for id: String) -> Int {
        guard let count = counts[id] else { return 0 }
        let frequency = min(count, 25) * 60

        guard let last = lastUsed[id] else { return frequency }
        let days = Date().timeIntervalSince(last) / 86_400
        let recency: Int
        switch days {
        case ..<1: recency = 1_200
        case ..<7: recency = 700
        case ..<30: recency = 300
        default: recency = 0
        }
        return frequency + recency
    }

    /// Most-used entries, for the empty-query state.
    func topIdentifiers(limit: Int) -> [String] {
        counts.keys
            .sorted { boost(for: $0) > boost(for: $1) }
            .prefix(limit)
            .map { $0 }
    }
}
