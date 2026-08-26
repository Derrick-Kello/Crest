//
//  Vocabulary.swift
//  Crest
//

import Foundation
import Observation

/// One thing the vocabulary knows.
///
/// Two kinds, because the two jobs are genuinely different:
///
/// - `.term` — a word the engine should know exists: "Crest", "Vercel". It only
///   feeds engine biasing; there is no wrong spelling to correct.
/// - `.correction` — when you hear X, write Y. "type script" → "TypeScript". Feeds both
///   biasing (on the correct form) and the rewrite pass.
nonisolated struct VocabularyEntry: Identifiable, Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case term
        case correction
    }

    var id: UUID
    var kind: Kind

    /// The correct text. For `.term` the word itself; for `.correction` what gets
    /// written. Either way this is what the engine is biased toward.
    var write: String

    /// For `.correction` only: the mishearing to look for. Empty for `.term`.
    var hear: String

    /// A disabled entry stays in the file but stops affecting anything, so a rule can
    /// be tested for usefulness without being deleted.
    var isEnabled: Bool

    /// Set on entries Crest added itself — app names, mostly. Kept apart from the
    /// user's own so a rebuild can replace them without touching anything hand-written.
    var isAutomatic: Bool

    init(
        id: UUID = UUID(),
        kind: Kind,
        write: String,
        hear: String = "",
        isEnabled: Bool = true,
        isAutomatic: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.write = write
        self.hear = hear
        self.isEnabled = isEnabled
        self.isAutomatic = isAutomatic
    }

    static func term(_ word: String) -> VocabularyEntry {
        VocabularyEntry(kind: .term, write: word)
    }

    static func correction(hear: String, write: String) -> VocabularyEntry {
        VocabularyEntry(kind: .correction, write: write, hear: hear)
    }

    /// How this entry reads in the plain-text file.
    var fileLine: String {
        let body = kind == .correction ? "\(hear) -> \(write)" : write
        return isEnabled ? body : "# off: \(body)"
    }
}

/// One correction that actually fired, kept so history can show whether the vocabulary
/// is earning its place rather than leaving it to faith.
nonisolated struct AppliedCorrection: Codable, Hashable, Sendable {
    /// The text as the engine produced it.
    let from: String
    /// What it was rewritten to.
    let to: String
    /// How many times it fired in this transcript.
    let count: Int
}

/// Rewrites transcribed text using the vocabulary's correction pairs.
///
/// This is the guaranteed half. Engine biasing is a nudge — it raises the odds of the
/// right word and promises nothing — so anything that must come out right has to be
/// fixed here, after the fact, deterministically.
///
/// Three rules, all load-bearing:
///
/// **Longest match first.** "Claude Code" is applied before "Claude", so the longer rule
/// is not pre-empted by a shorter one overlapping it.
///
/// **Whole matches only.** Every pattern is fenced by letter/digit lookarounds, so a rule
/// for "type script" can never bite into "typescripts".
///
/// **Glued words still match.** Engines run words together — "Crest", "disk-pilot" —
/// so the gap between parts is matched as optional whitespace or hyphens, not a literal
/// space.
nonisolated struct VocabularyCorrector: Sendable {
    private let rules: [Rule]

    private struct Rule: Sendable {
        let regex: NSRegularExpression
        let replacement: String
        let trigger: String
    }

    init(entries: [VocabularyEntry]) {
        let corrections = entries
            .filter { $0.isEnabled && $0.kind == .correction }
            .filter { !$0.hear.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.hear.count > $1.hear.count }

        rules = corrections.compactMap { entry in
            guard let regex = Self.makeRegex(for: entry.hear) else { return nil }
            return Rule(
                regex: regex,
                replacement: NSRegularExpression.escapedTemplate(for: entry.write),
                trigger: entry.hear
            )
        }
    }

    var isEmpty: Bool { rules.isEmpty }

    /// Applies every rule in order.
    ///
    /// - Returns: the rewritten text, plus one `AppliedCorrection` per rule that fired.
    func apply(to text: String) -> (text: String, applied: [AppliedCorrection]) {
        guard !rules.isEmpty, !text.isEmpty else { return (text, []) }

        // Normalized to NFC before matching. macOS hands back decomposed strings in
        // several places — a filesystem read of the vocabulary file being the obvious
        // one — and "café" decomposed is five scalars where composed is four. Pattern
        // and text must be in the same form or an accented trigger silently never fires.
        var result = text.precomposedStringWithCanonicalMapping
        var applied: [AppliedCorrection] = []

        for rule in rules {
            let range = NSRange(result.startIndex..., in: result)
            let matches = rule.regex.numberOfMatches(in: result, range: range)
            guard matches > 0 else { continue }

            // Records what the engine actually produced rather than the rule's trigger.
            // Seeing the real mishearing is the point, and it can differ in case or
            // spacing ("TypeScript" matched by "type script").
            let heard = rule.regex.firstMatch(in: result, range: range)
                .flatMap { Range($0.range, in: result) }
                .map { String(result[$0]) } ?? rule.trigger

            result = rule.regex.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: rule.replacement
            )

            applied.append(AppliedCorrection(
                from: heard,
                to: rule.replacement.replacingOccurrences(of: "\\", with: ""),
                count: matches
            ))
        }

        return (result, applied)
    }

    /// Builds the pattern for one trigger phrase.
    ///
    /// Parts are joined with `[\s\-]*` — zero or more spaces or hyphens — which is what
    /// catches "Crest" and "disk-pilot" alongside the spaced form.
    ///
    /// The fences are letter/digit lookarounds rather than `\b`, which would treat a
    /// trailing hyphen or apostrophe as a boundary and let a rule reach into a longer
    /// word.
    private static func makeRegex(for trigger: String) -> NSRegularExpression? {
        let parts = trigger
            .precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "\t" })
            .map { NSRegularExpression.escapedPattern(for: String($0)) }

        guard !parts.isEmpty else { return nil }

        let body = parts.joined(separator: "[\\s\\-]*")
        let pattern = "(?<![\\p{L}\\p{N}])\(body)(?![\\p{L}\\p{N}])"
        return try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    // MARK: - Engine biasing

    /// Deliberately short. These models drift when given a long context list — on quiet
    /// or ambiguous audio they start emitting the terms they were primed with, which is
    /// a far worse failure than the misspelling it was meant to prevent.
    static let biasLimit = 40

    /// - Returns: the correct spellings — `.term` words and the write side of
    ///   corrections — capped at `biasLimit`, user entries before automatic ones.
    static func biasPhrases(from entries: [VocabularyEntry]) -> [String] {
        var seen = Set<String>()
        var phrases: [String] = []

        // The user's own entries are the ones they care about, so they get the budget
        // first and an auto-indexed app name can never crowd one out.
        for entry in entries.filter({ !$0.isAutomatic }) + entries.filter(\.isAutomatic) {
            guard entry.isEnabled else { continue }
            let phrase = entry.write.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !phrase.isEmpty, seen.insert(phrase.lowercased()).inserted else { continue }
            phrases.append(phrase)
            if phrases.count == biasLimit { break }
        }

        return phrases
    }
}

/// The vocabulary, persisted as a plain text file you can edit by hand.
///
/// A text file rather than JSON, because it should be editable outside the UI and JSON
/// is only nominally that — quoting, escaping, and a trailing-comma trap for anyone
/// adding a line in a hurry. One entry per line:
///
/// ```
/// Anthropic
/// type script -> TypeScript
/// # off: some rule -> Rule
/// ```
///
/// The file is watched, so a hand edit shows up in the UI without a relaunch.
@MainActor
@Observable
final class VocabularyStore {
    static let shared = VocabularyStore()

    private(set) var entries: [VocabularyEntry] = []

    private var watcher: DispatchSourceFileSystemObject?
    /// Set while we are writing, so our own save does not read back as an outside edit.
    private var isSaving = false

    static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Crest", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("vocabulary.txt")
    }

    private init() {
        load()
        startWatching()
    }

    // MARK: - Editing

    func add(_ entry: VocabularyEntry) {
        entries.append(entry)
        save()
    }

    func update(_ entry: VocabularyEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index] = entry
        save()
    }

    func delete(_ entry: VocabularyEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func setEnabled(_ isEnabled: Bool, for entry: VocabularyEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index].isEnabled = isEnabled
        save()
    }

    /// Replaces the automatic entries with `names`, leaving hand-written ones alone.
    ///
    /// This is what makes app names transcribe correctly for free: Crest already
    /// indexes every app on the Mac for the command bar, and a name the engine has
    /// never heard of is exactly the kind of word biasing exists for. Only multi-word
    /// or unusual names are worth the budget — "Mail" and "Music" are ordinary words
    /// and priming on them would do more harm than good.
    func learn(appNames names: [String]) {
        let candidates = names
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { Self.isWorthBiasing($0) }
        let existing = Set(entries.filter { !$0.isAutomatic }.map { $0.write.lowercased() })

        var seen = Set<String>()
        let learned = candidates.compactMap { name -> VocabularyEntry? in
            let key = name.lowercased()
            guard !existing.contains(key), seen.insert(key).inserted else { return nil }
            return VocabularyEntry(kind: .term, write: name, isAutomatic: true)
        }

        let previous = entries.filter(\.isAutomatic).map(\.write)
        guard previous != learned.map(\.write) else { return }

        entries = entries.filter { !$0.isAutomatic } + learned
        save()
    }

    /// An app name earns a slot only if the engine plausibly gets it wrong: a proper
    /// noun with internal capitals, a digit, or more than one word. Single ordinary
    /// words are exactly what biasing should not be spent on.
    private static func isWorthBiasing(_ name: String) -> Bool {
        guard name.count >= 4, name.count <= 32 else { return false }
        guard name.rangeOfCharacter(from: .letters) != nil else { return false }
        if name.contains(" ") { return true }
        let body = name.dropFirst()
        return body.contains(where: \.isUppercase) || body.contains(where: \.isNumber)
    }

    /// Case- and diacritic-insensitive search across both sides of an entry.
    func filtered(by query: String) -> [VocabularyEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return entries }
        return entries.filter {
            $0.write.localizedStandardContains(trimmed) || $0.hear.localizedStandardContains(trimmed)
        }
    }

    /// A corrector over the current entries. Rebuilt on demand — compiling a few dozen
    /// small regexes is cheap next to transcription, and caching it invites staleness.
    var corrector: VocabularyCorrector { VocabularyCorrector(entries: entries) }

    var biasPhrases: [String] { VocabularyCorrector.biasPhrases(from: entries) }

    // MARK: - Persistence

    private func load() {
        guard let text = try? String(contentsOf: Self.fileURL, encoding: .utf8) else {
            entries = []
            return
        }
        entries = Self.parse(text)
    }

    nonisolated static func parse(_ text: String) -> [VocabularyEntry] {
        var isAutomatic = false

        return text.split(separator: "\n", omittingEmptySubsequences: false).compactMap { rawLine in
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { return nil }

            // Everything below the marker was written by Crest and is replaced
            // wholesale on the next index, so it has to survive a round trip labelled.
            if line == automaticMarker {
                isAutomatic = true
                return nil
            }

            // `# off:` is a disabled entry; any other comment is just a comment.
            var isEnabled = true
            if line.hasPrefix("#") {
                let stripped = line.dropFirst().trimmingCharacters(in: .whitespaces)
                guard stripped.lowercased().hasPrefix("off:") else { return nil }
                line = stripped.dropFirst(4).trimmingCharacters(in: .whitespaces)
                isEnabled = false
                guard !line.isEmpty else { return nil }
            }

            if let arrow = line.range(of: "->") {
                let hear = line[..<arrow.lowerBound].trimmingCharacters(in: .whitespaces)
                let write = line[arrow.upperBound...].trimmingCharacters(in: .whitespaces)
                guard !hear.isEmpty, !write.isEmpty else { return nil }
                return VocabularyEntry(
                    kind: .correction, write: write, hear: hear,
                    isEnabled: isEnabled, isAutomatic: isAutomatic
                )
            }

            return VocabularyEntry(
                kind: .term, write: line, isEnabled: isEnabled, isAutomatic: isAutomatic
            )
        }
    }

    private func save() {
        isSaving = true
        defer { isSaving = false }

        let mine = entries.filter { !$0.isAutomatic }.map(\.fileLine).joined(separator: "\n")
        let learned = entries.filter(\.isAutomatic).map(\.fileLine).joined(separator: "\n")

        var text = Self.header + mine + "\n"
        if !learned.isEmpty {
            text += "\n" + Self.automaticMarker + "\n" + learned + "\n"
        }
        try? text.write(to: Self.fileURL, atomically: true, encoding: .utf8)
    }

    nonisolated private static let automaticMarker = "# --- learned from your apps (rewritten automatically) ---"

    private static let header = """
        # Crest voice vocabulary
        #
        #   Anthropic                  a term — the engine is told this word exists
        #   type script -> TypeScript  a correction — when you hear X, write Y
        #   # off: some rule -> Rule   a disabled entry
        #
        # Edit this file directly if you like; Crest picks up changes immediately.

        """

    // MARK: - Outside edits

    /// Rearms after every event: an atomic write replaces the inode, so the descriptor
    /// we were watching is gone the moment the file changes — including when we save.
    private func startWatching() {
        watcher?.cancel()

        let descriptor = open(Self.fileURL.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .extend],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                if !self.isSaving { self.load() }
                self.startWatching()
            }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()

        watcher = source
    }
}
