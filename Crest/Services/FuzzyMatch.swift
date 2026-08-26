//
//  FuzzyMatch.swift
//  Crest
//

import Foundation

/// One searchable string belonging to an indexed item.
///
/// An item is rarely findable by a single string. "Visual Studio Code" is also
/// "vscode" and "com.microsoft.VSCode"; System Settings' Displays pane is also
/// "monitor" and "resolution". Each of those is a key, and `weight` says how much
/// a hit on it is worth relative to the item's real name — a bundle-identifier
/// match should never outrank someone typing the actual name of something else.
nonisolated struct MatchKey: Sendable, Hashable {
    /// Already normalized: lowercased, diacritics folded.
    let text: String
    /// Initials of `text`, precomputed so matching never walks the string twice.
    let initials: String
    /// Percentage of the raw score this key keeps. 100 is the item's own name.
    let weight: Int

    init(_ raw: String, weight: Int = 100) {
        text = FuzzyMatch.normalize(raw)
        initials = FuzzyMatch.initials(of: raw)
        self.weight = weight
    }
}

/// Ranks a typed query against an item's searchable keys.
///
/// The tiers are ordered the way a launcher is expected to behave: an exact name
/// beats a prefix, a prefix beats initials, initials beat a word start, a word
/// start beats a substring, and a scattered subsequence comes last. Every tier is
/// separated by a wide band so a weaker key can never climb into a stronger tier
/// — a 60-weight bundle-identifier prefix stays below a 100-weight name prefix.
nonisolated enum FuzzyMatch {

    // MARK: - Normalisation

    /// Lowercases and strips diacritics so "Café" is reachable by typing "cafe".
    static func normalize(_ raw: String) -> String {
        raw.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    }

    /// First letter of each word, plus internal capitals, so "Activity Monitor"
    /// yields "am" and "VSCodium" yields "vc" — which is what people actually type.
    static func initials(of raw: String) -> String {
        var result = ""
        var previousWasBoundary = true
        var previousWasLower = false

        for character in raw {
            if character.isWhitespace || character == "-" || character == "_"
                || character == "." || character == "&" || character == "/" {
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

    /// Splits what the user typed into tokens. "act mon" is two tokens, and both
    /// have to land somewhere for the item to be considered a match at all.
    static func tokenize(_ query: String) -> [String] {
        normalize(query)
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
    }

    // MARK: - Entry point

    /// Best score across every key, or nil if nothing matched.
    ///
    /// `tokens` must come from `tokenize` and `joined` is those tokens run
    /// together — both are passed in rather than derived here because the caller
    /// scores thousands of items per keystroke and computing them once matters.
    static func score(tokens: [String], joined: String, keys: [MatchKey]) -> Int? {
        guard !joined.isEmpty else { return 0 }

        var best: Int?
        for key in keys {
            guard var raw = singleScore(query: joined, key: key) else {
                // A multi-word query rarely appears verbatim in the name. "act mon"
                // is not a substring of "activity monitor", so fall back to
                // scoring each token separately before giving up on this key.
                if tokens.count > 1, let spread = tokenScore(tokens: tokens, key: key) {
                    let weighted = spread * key.weight / 100
                    best = max(best ?? Int.min, weighted)
                }
                continue
            }
            // A space-separated query that does match verbatim is a strong signal,
            // so it keeps its tier; the token fallback below is always weaker.
            if tokens.count > 1, let spread = tokenScore(tokens: tokens, key: key) {
                raw = max(raw, spread)
            }
            best = max(best ?? Int.min, raw * key.weight / 100)
        }
        return best
    }

    /// Convenience for callers with a single name and no precomputed query.
    static func score(query: String, keys: [MatchKey]) -> Int? {
        let tokens = tokenize(query)
        return score(tokens: tokens, joined: tokens.joined(), keys: keys)
    }

    // MARK: - Tiers

    private static func singleScore(query: String, key: MatchKey) -> Int? {
        let candidate = key.text
        guard !candidate.isEmpty else { return nil }

        if candidate == query { return 120_000 }
        if candidate.hasPrefix(query) { return 100_000 - min(candidate.count, 60) * 10 }
        if key.initials == query { return 90_000 }
        if key.initials.hasPrefix(query) { return 80_000 - min(key.initials.count, 40) * 10 }

        if let wordScore = wordPrefixScore(query: query, candidate: candidate) {
            return wordScore
        }

        if let range = candidate.range(of: query) {
            let offset = candidate.distance(from: candidate.startIndex, to: range.lowerBound)
            return 50_000 - min(offset * 100, 9_000)
        }

        return subsequenceScore(query: query, candidate: candidate)
    }

    /// The query starting a word inside the name: "code" → "Visual Studio Code".
    /// Earlier words score higher, so "code" still prefers "Code" to "Xcode Tools".
    private static func wordPrefixScore(query: String, candidate: String) -> Int? {
        var best: Int?
        var wordNumber = 0
        var index = candidate.startIndex

        while index < candidate.endIndex {
            let isWordStart: Bool
            if index == candidate.startIndex {
                isWordStart = true
            } else {
                let previous = candidate[candidate.index(before: index)]
                isWordStart = previous == " " || previous == "-" || previous == "_" || previous == "."
                if isWordStart { wordNumber += 1 }
            }
            if isWordStart, candidate[index...].hasPrefix(query) {
                best = max(best ?? 0, 70_000 - min(wordNumber * 1_000, 9_000))
            }
            index = candidate.index(after: index)
        }
        return best
    }

    /// Every query character appears in order. Consecutive runs and word starts
    /// score higher, so "actmon" ranks Activity Monitor well while a coincidental
    /// scattering of the same letters lands near the floor of the tier.
    private static func subsequenceScore(query: String, candidate: String) -> Int? {
        // A query far longer than the name cannot be a subsequence, and checking
        // first avoids walking every candidate for a long paste into the field.
        guard query.count <= candidate.count else { return nil }

        var score = 0
        var streak = 0
        var gaps = 0
        var index = candidate.startIndex
        var previousWasBoundary = true

        for character in query {
            var matched = false
            while index < candidate.endIndex {
                let current = candidate[index]
                index = candidate.index(after: index)
                if current == character {
                    streak += 1
                    score += 30 + streak * 8 + (previousWasBoundary ? 60 : 0)
                    previousWasBoundary = false
                    matched = true
                    break
                }
                streak = 0
                gaps += 1
                previousWasBoundary = current == " " || current == "-" || current == "_" || current == "."
            }
            guard matched else { return nil }
        }
        // Shorter names win ties: "Mail" over "Mailbox Assistant" for "mail", and
        // a match that skipped half the string is worth less than a tight one.
        return 20_000 + score - min(gaps * 20, 4_000) - min(candidate.count * 10, 4_000)
    }

    /// Scores a multi-word query by matching each token independently.
    ///
    /// Every token must hit, otherwise typing a second word could never narrow the
    /// list. Tokens that land on word starts score far above tokens that merely
    /// appear somewhere, which is what makes "act mon" find Activity Monitor
    /// instead of every app containing both letter runs.
    private static func tokenScore(tokens: [String], key: MatchKey) -> Int? {
        let candidate = key.text
        var total = 0
        var searchStart = candidate.startIndex
        var allInOrder = true

        for token in tokens {
            guard let hit = firstHit(of: token, in: candidate, from: searchStart) else {
                // Out of order is still a match, just a weaker one: "monitor
                // activity" should find Activity Monitor, below "activity monitor".
                guard let anywhere = firstHit(of: token, in: candidate, from: candidate.startIndex) else {
                    return nil
                }
                allInOrder = false
                total += anywhere.isWordStart ? 900 : 300
                continue
            }
            total += hit.isWordStart ? 1_200 : 400
            searchStart = hit.end
        }

        let base = 60_000 + total / max(tokens.count, 1)
        return allInOrder ? base : base - 8_000
    }

    private static func firstHit(
        of token: String, in candidate: String, from start: String.Index
    ) -> (end: String.Index, isWordStart: Bool)? {
        guard let range = candidate.range(of: token, range: start..<candidate.endIndex) else {
            return nil
        }
        let isWordStart: Bool
        if range.lowerBound == candidate.startIndex {
            isWordStart = true
        } else {
            let previous = candidate[candidate.index(before: range.lowerBound)]
            isWordStart = previous == " " || previous == "-" || previous == "_" || previous == "."
        }
        return (range.upperBound, isWordStart)
    }
}
