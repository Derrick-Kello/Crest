//
//  DictationAnalytics.swift
//  Crest
//

import Foundation

/// What dictation has actually done for you, computed from the history.
///
/// A value type built from the entries rather than figures scattered across the store,
/// because every number here is a derivation the UI should not be doing inline and the
/// arithmetic is worth testing on its own.
nonisolated struct DictationAnalytics: Sendable {
    let count: Int
    let words: Int
    /// How fast you talk, in words per minute. Median rather than mean.
    let speakingRate: Int?
    /// Release to text on screen. Median, because one slow run drags an average around
    /// far more than it says about the typical experience.
    let medianLatency: TimeInterval?
    /// Signed seconds against typing the same words by hand. Negative is possible and is
    /// reported as it comes out.
    let timeSaved: TimeInterval
    let countToday: Int
    let wordsThisWeek: Int
    /// Vocabulary rewrites that fired, so the vocabulary's usefulness is a number rather
    /// than a matter of faith.
    let corrections: Int
    let topApplication: String?
    let topApplicationCount: Int

    /// The typing speed the saving is measured against, carried so the UI can label the
    /// figure with its own assumption instead of presenting it as fact.
    let typingWordsPerMinute: Int

    /// - Parameter typingWordsPerMinute: what the user says they type at. The whole
    ///   saving figure hinges on it, which is exactly why it is a setting and is printed
    ///   next to the number rather than buried as a constant.
    init(
        entries: [Dictation],
        typingWordsPerMinute: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        self.typingWordsPerMinute = typingWordsPerMinute
        count = entries.count
        words = entries.reduce(0) { $0 + $1.wordCount }
        corrections = entries.reduce(0) { total, entry in
            total + (entry.corrections ?? []).reduce(0) { $0 + $1.count }
        }

        speakingRate = Self.median(entries.map(\.wordsPerMinute).filter { $0 > 0 })
        medianLatency = Self.median(entries.map(\.processSeconds))

        // Speaking is only faster than typing once the words outrun the wait. This is
        // the honest form of that: what those words would have cost to type, minus what
        // they actually cost — the time held plus the time spent waiting for the text.
        // A three-word utterance comes out negative, and summing it signed is the point.
        let rate = max(1, typingWordsPerMinute)
        timeSaved = entries.reduce(0) { total, entry in
            let typing = Double(entry.wordCount) / Double(rate) * 60
            return total + (typing - (entry.audioSeconds + entry.processSeconds))
        }

        let startOfToday = calendar.startOfDay(for: now)
        countToday = entries.count { $0.date >= startOfToday }

        let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        wordsThisWeek = entries.filter { $0.date >= weekAgo }.reduce(0) { $0 + $1.wordCount }

        var perApplication: [String: Int] = [:]
        for entry in entries {
            guard let name = entry.appName else { continue }
            perApplication[name, default: 0] += 1
        }
        let top = perApplication.max { left, right in
            // Ties broken by name, so the row does not swap around between launches for
            // no visible reason.
            left.value == right.value ? left.key > right.key : left.value < right.value
        }
        topApplication = top?.key
        topApplicationCount = top?.value ?? 0
    }

    var isEmpty: Bool { count == 0 }

    private static func median(_ values: [Int]) -> Int? {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return nil }
        return sorted[sorted.count / 2]
    }

    private static func median(_ values: [TimeInterval]) -> TimeInterval? {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return nil }
        return sorted[sorted.count / 2]
    }
}

/// Durations as a person would say them. Shared by both analytics surfaces.
nonisolated enum DurationText {
    /// Compact and signed: "12 min", "1h 4m", "−30s".
    static func string(_ seconds: TimeInterval) -> String {
        let sign = seconds < 0 ? "−" : ""
        let total = Int(abs(seconds).rounded())

        if total < 60 { return "\(sign)\(total)s" }
        let minutes = total / 60
        if minutes < 60 { return "\(sign)\(minutes) min" }
        return "\(sign)\(minutes / 60)h \(minutes % 60)m"
    }
}
