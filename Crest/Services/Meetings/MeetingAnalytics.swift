//
//  MeetingAnalytics.swift
//  Crest
//

import Foundation

/// What your meetings add up to, computed from the index rather than the transcripts.
///
/// Reading the index is the whole point: every figure here is available without decoding
/// a single transcript, so the Meetings tab costs one small file read however many
/// meetings are stored.
nonisolated struct MeetingAnalytics: Sendable {
    let count: Int
    let totalDuration: TimeInterval
    let averageDuration: TimeInterval
    let countThisWeek: Int
    let durationThisWeek: TimeInterval
    let longest: TimeInterval
    let words: Int
    /// Your share of the words, across the meetings where both sides were actually
    /// recorded. Meetings with only one side captured are left out entirely rather than
    /// counted as 100% you.
    let talkShare: Double?
    let actionItems: Int
    let summarized: Int
    let bytes: UInt64
    let topApplication: String?
    let topApplicationCount: Int

    init(rows: [MeetingSummaryRow], now: Date = Date(), calendar: Calendar = .current) {
        count = rows.count
        totalDuration = rows.reduce(0) { $0 + $1.duration }
        averageDuration = rows.isEmpty ? 0 : totalDuration / Double(rows.count)
        longest = rows.map(\.duration).max() ?? 0
        words = rows.reduce(0) { $0 + $1.wordCount }
        actionItems = rows.reduce(0) { $0 + $1.actionItemCount }
        summarized = rows.count(where: \.isSummarized)
        bytes = rows.reduce(UInt64(0)) { $0 + $1.bytes }

        let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        let recent = rows.filter { $0.startedAt >= weekAgo }
        countThisWeek = recent.count
        durationThisWeek = recent.reduce(0) { $0 + $1.duration }

        // Weighted by words, not by averaging each meeting's percentage. Averaging the
        // percentages lets a two-minute call where you said one word count as heavily as
        // an hour-long one, which is not what "how much do I talk" means.
        let twoSided = rows.filter(\.hasBothSides)
        let yours = twoSided.reduce(0) { $0 + $1.yourWords }
        let theirs = twoSided.reduce(0) { $0 + $1.otherWords }
        talkShare = (yours + theirs) > 0 ? Double(yours) / Double(yours + theirs) : nil

        var perApplication: [String: Int] = [:]
        for row in rows {
            guard let name = row.applicationName else { continue }
            perApplication[name, default: 0] += 1
        }
        let top = perApplication.max { left, right in
            // Ties broken by name, so the row does not swap around between launches.
            left.value == right.value ? left.key > right.key : left.value < right.value
        }
        topApplication = top?.key
        topApplicationCount = top?.value ?? 0
    }

    var isEmpty: Bool { count == 0 }

    /// Meetings still waiting to be summarized.
    var unsummarized: Int { count - summarized }
}
