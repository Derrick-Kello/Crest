//
//  DictationHistory.swift
//  Crest
//

import Foundation
import Observation

/// One finished dictation.
nonisolated struct Dictation: Codable, Sendable, Identifiable, Hashable {
    var id: UUID
    let date: Date
    /// The text that was actually typed.
    let text: String
    /// Where it went, for the history row and for per-app style overrides.
    let appName: String?
    let bundleIdentifier: String?
    let style: DictationStyle
    /// How long the key was held.
    let audioSeconds: Double
    /// Release → text ready. This is the latency you actually feel, and the only number
    /// on which a streaming engine and a batch engine compare honestly.
    let processSeconds: Double
    /// Vocabulary corrections that fired, so the vocabulary's usefulness is visible
    /// rather than a matter of faith.
    var corrections: [AppliedCorrection]?

    init(
        id: UUID = UUID(),
        date: Date,
        text: String,
        appName: String?,
        bundleIdentifier: String?,
        style: DictationStyle,
        audioSeconds: Double,
        processSeconds: Double,
        corrections: [AppliedCorrection]? = nil
    ) {
        self.id = id
        self.date = date
        self.text = text
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.style = style
        self.audioSeconds = audioSeconds
        self.processSeconds = processSeconds
        self.corrections = corrections
    }

    var wordCount: Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }

    /// Words per minute of speech. The figure people quote when they say dictation is
    /// faster than typing, and the one worth showing back to them.
    var wordsPerMinute: Int {
        guard audioSeconds > 0.4 else { return 0 }
        return Int((Double(wordCount) / audioSeconds) * 60)
    }
}

/// Appends every dictation to a JSONL file and keeps the recent ones in memory.
///
/// JSONL rather than one JSON array, because the hot path is an append after every
/// utterance and rewriting the whole file for each one gets slower the longer you use
/// the app.
@MainActor
@Observable
final class DictationHistory {
    static let shared = DictationHistory()

    private(set) var entries: [Dictation] = []

    /// Past this the file is rewritten with the newest `keepCount`. History is a
    /// convenience, not an archive, and an unbounded log of everything you have ever
    /// said is a liability rather than a feature.
    private static let keepCount = 400

    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Crest", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("dictations.jsonl")
    }

    private init() {
        entries = Self.load()
    }

    // MARK: - Figures

    /// Recomputed on read rather than cached. It is a pass over a few hundred small
    /// values, and a cache would need invalidating from every edit path for no gain.
    ///
    /// The typing speed is passed in rather than read from the settings here, so this
    /// type stays a store over its own entries and the figure can be computed for any
    /// baseline without changing what the user has saved.
    func analytics(typingWordsPerMinute: Int) -> DictationAnalytics {
        DictationAnalytics(entries: entries, typingWordsPerMinute: typingWordsPerMinute)
    }

    // MARK: - Editing

    func record(_ dictation: Dictation) {
        entries.insert(dictation, at: 0)
        append(dictation)
        if entries.count > Self.keepCount {
            entries = Array(entries.prefix(Self.keepCount))
            rewrite()
        }
    }

    func delete(_ dictation: Dictation) {
        entries.removeAll { $0.id == dictation.id }
        rewrite()
    }

    func clear() {
        entries = []
        try? FileManager.default.removeItem(at: Self.fileURL)
    }

    // MARK: - Persistence

    private static func load() -> [Dictation] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let all = data.split(separator: 0x0A).compactMap {
            try? decoder.decode(Dictation.self, from: Data($0))
        }
        return all.reversed()
    }

    private func append(_ dictation: Dictation) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard var line = try? encoder.encode(dictation) else { return }
        line.append(0x0A)

        if let handle = try? FileHandle(forWritingTo: Self.fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: Self.fileURL)
        }
    }

    /// Replaces the whole file. Deleting cannot be an append, and the trim above needs
    /// the same path. Atomic, because a partial write here loses history nobody asked to
    /// delete.
    private func rewrite() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let body = entries.reversed().compactMap { entry -> String? in
            guard let data = try? encoder.encode(entry) else { return nil }
            return String(data: data, encoding: .utf8)
        }.joined(separator: "\n")

        try? (body.isEmpty ? "" : body + "\n")
            .write(to: Self.fileURL, atomically: true, encoding: .utf8)
    }
}
