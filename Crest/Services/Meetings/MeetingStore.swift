//
//  MeetingStore.swift
//  Crest
//

import Foundation
import Observation
import OSLog

/// One stretch of speech from one side of the call.
nonisolated struct TranscriptSegment: Codable, Sendable, Identifiable, Hashable {
    var id: UUID = UUID()
    /// Which capture it came from. This is the whole of the speaker attribution: two
    /// separate captures mean "you" and "everyone else" never have to be told apart by a
    /// diarization model that would need its own download and would still guess.
    let source: AudioSource
    /// Seconds from the start of the meeting, so the transcript reads as a timeline.
    let offset: TimeInterval
    var text: String
}

/// A structured summary of a meeting, produced on-device.
nonisolated struct MeetingSummary: Codable, Sendable, Hashable {
    /// One sentence: what this meeting was.
    var headline: String
    /// The narrative summary, a short paragraph.
    var overview: String
    var keyPoints: [String]
    var decisions: [String]
    var actionItems: [MeetingActionItem]
    var openQuestions: [String]
    /// When it was produced, so a summary from before the transcript was extended is
    /// visibly stale rather than quietly wrong.
    var generatedAt: Date
}

nonisolated struct MeetingActionItem: Codable, Sendable, Hashable, Identifiable {
    var id: UUID = UUID()
    var task: String
    /// Who took it on. "Unassigned" when the transcript never says.
    var owner: String
}

/// A recorded meeting: its transcript, and what was made of it.
nonisolated struct Meeting: Codable, Sendable, Identifiable, Hashable {
    var id: UUID
    var title: String
    var startedAt: Date
    var endedAt: Date?
    var segments: [TranscriptSegment]
    var summary: MeetingSummary?
    /// The app that was in the call, when one could be identified. Recorded because it
    /// is the most reliable thing anyone remembers about a meeting from three weeks ago.
    var applicationName: String?

    init(
        id: UUID = UUID(),
        title: String,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        segments: [TranscriptSegment] = [],
        summary: MeetingSummary? = nil,
        applicationName: String? = nil
    ) {
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.segments = segments
        self.summary = summary
        self.applicationName = applicationName
    }

    var duration: TimeInterval {
        (endedAt ?? Date()).timeIntervalSince(startedAt)
    }

    var wordCount: Int {
        segments.reduce(0) { total, segment in
            total + segment.text.split { $0.isWhitespace || $0.isNewline }.count
        }
    }

    func wordCount(from source: AudioSource) -> Int {
        segments.reduce(0) { total, segment in
            guard segment.source == source else { return total }
            return total + segment.text.split { $0.isWhitespace || $0.isNewline }.count
        }
    }

    /// The transcript as one attributed block, which is what the summarizer reads and
    /// what an export writes out.
    var plainTranscript: String {
        segments.map { "\($0.source.speakerLabel): \($0.text)" }.joined(separator: "\n")
    }

    var isEmpty: Bool {
        segments.allSatisfy { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// Markdown, for pasting into wherever notes actually live.
    func markdown() -> String {
        var lines: [String] = ["# \(title)"]

        let stamp = startedAt.formatted(date: .abbreviated, time: .shortened)
        var meta = stamp
        if let applicationName { meta += " · \(applicationName)" }
        meta += " · \(DurationText.string(duration))"
        lines.append("")
        lines.append(meta)

        if let summary {
            lines.append("")
            lines.append("## Summary")
            lines.append("")
            lines.append(summary.overview)

            if !summary.keyPoints.isEmpty {
                lines.append("")
                lines.append("## Key points")
                lines.append("")
                lines.append(contentsOf: summary.keyPoints.map { "- \($0)" })
            }
            if !summary.decisions.isEmpty {
                lines.append("")
                lines.append("## Decisions")
                lines.append("")
                lines.append(contentsOf: summary.decisions.map { "- \($0)" })
            }
            if !summary.actionItems.isEmpty {
                lines.append("")
                lines.append("## Action items")
                lines.append("")
                lines.append(contentsOf: summary.actionItems.map { "- [ ] \($0.task) — \($0.owner)" })
            }
            if !summary.openQuestions.isEmpty {
                lines.append("")
                lines.append("## Open questions")
                lines.append("")
                lines.append(contentsOf: summary.openQuestions.map { "- \($0)" })
            }
        }

        lines.append("")
        lines.append("## Transcript")
        lines.append("")
        for segment in segments {
            lines.append("**\(Self.timestamp(segment.offset)) \(segment.source.speakerLabel):** \(segment.text)")
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    static func timestamp(_ offset: TimeInterval) -> String {
        let total = Int(offset.rounded())
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

}

/// The lightweight row shown in a list, so opening the panel does not decode every
/// transcript the user has ever recorded.
nonisolated struct MeetingSummaryRow: Codable, Sendable, Identifiable, Hashable {
    let id: UUID
    var title: String
    var startedAt: Date
    var duration: TimeInterval
    var applicationName: String?
    var headline: String?
    var actionItemCount: Int
    var wordCount: Int
    /// Words from the microphone, and words from everything else. Kept apart because the
    /// split is the interesting figure and recomputing it means decoding the transcript.
    var yourWords: Int
    var otherWords: Int
    /// False when the other side was never captured — no screen-recording grant, or the
    /// setting switched off. Without it a solo recording reads as "you talked 100% of
    /// the time", which is true and completely misleading.
    var hasBothSides: Bool
    /// What this transcript costs on disk. Crest is a disk tool; a feature of it
    /// that quietly accumulates files should say how many.
    var bytes: UInt64

    var isSummarized: Bool { headline != nil }

    /// Your share of the words spoken, or nil when only one side was recorded.
    var talkShare: Double? {
        guard hasBothSides else { return nil }
        let total = yourWords + otherWords
        guard total > 0 else { return nil }
        return Double(yourWords) / Double(total)
    }

    init(_ meeting: Meeting, bytes: UInt64 = 0) {
        id = meeting.id
        title = meeting.title
        startedAt = meeting.startedAt
        duration = meeting.duration
        applicationName = meeting.applicationName
        headline = meeting.summary?.headline
        actionItemCount = meeting.summary?.actionItems.count ?? 0
        wordCount = meeting.wordCount
        yourWords = meeting.wordCount(from: .microphone)
        otherWords = meeting.wordCount(from: .system)
        hasBothSides = meeting.segments.contains { $0.source == .system }
            && meeting.segments.contains { $0.source == .microphone }
        self.bytes = bytes
    }
}

/// Meetings on disk: one JSON file each, plus an index of the rows.
///
/// The index exists so the list is instant and costs one small read, rather than
/// decoding every transcript at launch to render a handful of titles. It is derived
/// data — if it is ever lost or corrupt it is rebuilt by reading the directory.
@MainActor
@Observable
final class MeetingStore {
    static let shared = MeetingStore()

    private(set) var rows: [MeetingSummaryRow] = []

    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Crest/Meetings", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private static var indexURL: URL { directory.appendingPathComponent("index.json") }

    private static func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }

    private init() {
        rows = Self.loadIndex() ?? Self.rebuildIndex()
    }

    // MARK: - Reading

    func meeting(id: UUID) -> Meeting? {
        guard let data = try? Data(contentsOf: Self.fileURL(for: id)) else { return nil }
        return try? Self.decoder.decode(Meeting.self, from: data)
    }

    /// Every figure the Meetings tab shows, from the index alone — no transcript is
    /// decoded to draw the tab.
    var analytics: MeetingAnalytics { MeetingAnalytics(rows: rows) }

    // MARK: - Writing

    func save(_ meeting: Meeting) {
        guard let data = try? Self.encoder.encode(meeting) else { return }
        try? data.write(to: Self.fileURL(for: meeting.id), options: .atomic)

        // Taken from the encoded bytes rather than by stat-ing the file back: it is the
        // same number, and it costs nothing here.
        let row = MeetingSummaryRow(meeting, bytes: UInt64(data.count))
        if let index = rows.firstIndex(where: { $0.id == meeting.id }) {
            rows[index] = row
        } else {
            rows.insert(row, at: 0)
        }
        rows.sort { $0.startedAt > $1.startedAt }
        writeIndex()
    }

    func rename(id: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var meeting = meeting(id: id) else { return }
        meeting.title = trimmed
        save(meeting)
    }

    func delete(id: UUID) {
        try? FileManager.default.removeItem(at: Self.fileURL(for: id))
        rows.removeAll { $0.id == id }
        writeIndex()
    }

    func deleteAll() {
        for row in rows { try? FileManager.default.removeItem(at: Self.fileURL(for: row.id)) }
        rows = []
        writeIndex()
    }

    // MARK: - Index

    private func writeIndex() {
        guard let data = try? Self.encoder.encode(rows) else { return }
        try? data.write(to: Self.indexURL, options: .atomic)
    }

    private static func loadIndex() -> [MeetingSummaryRow]? {
        guard let data = try? Data(contentsOf: indexURL) else { return nil }
        return try? decoder.decode([MeetingSummaryRow].self, from: data)
    }

    /// Reads every meeting file and rebuilds the index from it.
    ///
    /// Runs when the index is missing or unreadable, which makes the index safe to
    /// delete — and is also the migration path. An index written by an older release is
    /// missing the keys a newer `MeetingSummaryRow` needs, fails to decode, and is
    /// rebuilt from the transcripts, which are the real data and never change shape.
    private static func rebuildIndex() -> [MeetingSummaryRow] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )) ?? []

        let rows = files
            .filter { $0.pathExtension == "json" && $0.lastPathComponent != "index.json" }
            .compactMap { url -> MeetingSummaryRow? in
                guard let data = try? Data(contentsOf: url),
                      let meeting = try? decoder.decode(Meeting.self, from: data)
                else { return nil }
                return MeetingSummaryRow(meeting, bytes: UInt64(data.count))
            }
            .sorted { $0.startedAt > $1.startedAt }
        if let data = try? encoder.encode(rows) {
            try? data.write(to: indexURL, options: .atomic)
        }
        return rows
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
