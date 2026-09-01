//
//  CommandBarService.swift
//  Crest
//

import AppKit
import Foundation

/// Builds and searches the command bar catalog.
///
/// The catalog is built once in the background at launch and covers everything a
/// launcher is expected to reach: installed applications, System Settings panes,
/// system commands, and Crest's own tools. Matching afterwards is pure
/// in-memory string work, so every keystroke is answered without touching disk.
///
/// Nothing here calls out to a network or a model. Ranking is the fuzzy matcher
/// plus a local frecency table, which is what makes the bar work on a plane and
/// what keeps every query the user types on this machine.
@MainActor
@Observable
final class CommandBarService {
    static let shared = CommandBarService()

    /// The whole catalog, apps first.
    private(set) var items: [CatalogItem] = []
    /// Bumped whenever the catalog changes so views can re-run their query. The
    /// scan lands after the bar is already open on a cold launch, and without this
    /// the first search would show whatever was there when the view appeared.
    private(set) var indexGeneration = 0
    private(set) var isIndexing = false

    /// Applications only, for the uninstaller's picker.
    var apps: [CatalogItem] { items.filter { $0.category == .application } }

    private var history = Preferences.launchHistory
    private var iconCache: [String: NSImage] = [:]
    private var indexTask: Task<Void, Never>?

    private let fileSearch = FileSearchService.shared
    private let aliases = AliasStore.shared

    private init() {}

    // MARK: - Index

    /// Safe to call repeatedly; the scan runs once unless `force` is set.
    func buildIndex(force: Bool = false) {
        if !force, !items.isEmpty || isIndexing { return }
        indexTask?.cancel()
        isIndexing = true

        indexTask = Task { [weak self] in
            // Apps, the system catalog and the folder walk are independent, so
            // they run concurrently — the app walk is the slow half and neither
            // of the others should be waiting behind it.
            async let apps = Task.detached(priority: .userInitiated) { AppIndex.scan() }.value
            async let system = Task.detached(priority: .userInitiated) { SystemCatalog.scan() }.value
            async let folders = Task.detached(priority: .userInitiated) { FolderIndex.scan() }.value
            let scanned = await apps + system + folders

            guard !Task.isCancelled, let self else { return }
            self.items = scanned
            self.iconCache.removeAll()
            // An alias pointing at an app that has since been uninstalled is a
            // row in Settings claiming a word that nothing answers to.
            self.aliases.prune(keeping: Set(scanned.map(\.id)))
            self.indexGeneration += 1
            self.isIndexing = false
        }
    }

    /// Icons come from `NSWorkspace`, which hits the disk. The command bar draws
    /// up to a dozen rows per keystroke, so each one is fetched at most once.
    func icon(forApp path: String) -> NSImage {
        if let cached = iconCache[path] { return cached }
        let icon = NSWorkspace.shared.icon(forFile: path)
        icon.size = NSSize(width: 22, height: 22)
        // Bounded: a few hundred icons is fine, unbounded growth is not.
        if iconCache.count > 400 { iconCache.removeAll() }
        iconCache[path] = icon
        return icon
    }

    // MARK: - Search

    /// The maximum number of rows the bar will ever show.
    static let resultLimit = 14

    func results(for query: String) -> [CommandEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            fileSearch.cancel()
            return defaultEntries()
        }

        let parsed = Query(raw: trimmed)

        // A path typed in full is not a search — it is an address. Answering it
        // with fuzzy name matches would be ignoring what the user actually said.
        if let literal = parsed.literalPathEntries() {
            fileSearch.cancel()
            return literal
        }

        let tokens = FuzzyMatch.tokenize(parsed.text)
        let joined = tokens.joined()

        // Spotlight runs on its own clock; this only kicks it off, and its results
        // are folded in below from whatever the last round produced.
        fileSearch.search(parsed.text, mode: parsed.scope)

        if parsed.scope != .mixed {
            // A scoped search is an explicit request for files, so the catalog
            // steps aside — except for the indexed folders, which are the fastest
            // and most likely answer to a folder query and are already in hand
            // while Spotlight is still thinking.
            var scoped: [CommandEntry] = []
            if parsed.scope == .folders {
                for item in items where item.id.hasPrefix("folder:") {
                    guard let base = FuzzyMatch.score(tokens: tokens, joined: joined, keys: item.keys) else { continue }
                    scoped.append(CommandEntry(item: item, score: base + 40_000))
                }
            }
            scoped.append(contentsOf: fileSearch.results.map { CommandEntry(item: $0, score: 15_000) })
            return Array(scoped.sorted(by: Self.rank).prefix(Self.resultLimit))
        }

        var entries: [CommandEntry] = []

        if let answer = Self.evaluateExpression(parsed.text) {
            entries.append(CommandEntry(
                item: CatalogItem(
                    id: "answer",
                    title: answer,
                    subtitle: "\(parsed.text) — press ↩ to copy",
                    category: .answer,
                    symbolName: "equal.square",
                    keys: [],
                    action: .copyText(answer)
                ),
                score: 1_000_000
            ))
        }

        // An alias typed whole is the least ambiguous thing a user can type: they
        // chose the word and they chose what it points at. It pins to the top
        // rather than competing on fuzzy score, where a two-letter alias would
        // lose to every app whose name happens to contain those letters.
        let pinned = aliases.identifier(matching: parsed.text)

        for item in items {
            let keys = item.keys + aliases.matchKeys(for: item.id)
            guard let base = FuzzyMatch.score(tokens: tokens, joined: joined, keys: keys) else {
                continue
            }
            let bonus = item.id == pinned ? Self.aliasPinScore : 0
            entries.append(CommandEntry(item: item, score: base + bonus + history.boost(for: item.id)))
        }

        // Clipboard entries match on their text, which is arbitrary and often long,
        // so they are scored down hard — otherwise a paragraph you copied once
        // would outrank the app you open every day.
        for entry in ClipboardService.shared.entries.prefix(40) {
            guard let base = FuzzyMatch.score(
                tokens: tokens, joined: joined, keys: [MatchKey(entry.preview)]
            ) else { continue }
            entries.append(CommandEntry(
                item: CatalogItem(
                    id: "clip:" + entry.id.uuidString,
                    title: entry.preview,
                    subtitle: "Press ↩ to copy",
                    category: .clipboard,
                    symbolName: "doc.on.clipboard",
                    keys: [],
                    action: .copyText(entry.preview)
                ),
                score: base / 3
            ))
        }

        // Spotlight results arrive already ranked against each other by
        // `FileRanking`, and that order is preserved here rather than flattened
        // to one score — otherwise the six rows files are allowed would be filled
        // in whatever order Spotlight returned them, which is the bug that kept
        // folders off the list.
        for (offset, item) in fileSearch.results.enumerated() {
            entries.append(CommandEntry(item: item, score: 15_000 - offset))
        }

        return Array(pruned(entries).sorted(by: Self.rank).prefix(Self.resultLimit))
    }

    /// Enough to clear the strongest fuzzy tier, so an alias always wins outright.
    private static let aliasPinScore = 500_000

    /// What the user typed, after the prefixes that change the kind of search.
    ///
    /// Raycast-style scoping, kept to the three that earn their keystrokes: `f `
    /// for files only, `d ` for folders only, and a literal path for this exact
    /// thing. Anything else is a plain search, because a launcher that needs a
    /// syntax cheat sheet is a shell with extra steps.
    struct Query {
        let text: String
        let scope: FileSearchService.Mode
        let literalPath: String?

        init(raw: String) {
            if raw.hasPrefix("/") || raw.hasPrefix("~/") {
                let expanded = (raw as NSString).expandingTildeInPath
                text = raw
                scope = .dedicated
                literalPath = FileManager.default.fileExists(atPath: expanded) ? expanded : nil
                return
            }
            for prefix in ["folder ", "dir ", "d "] where raw.lowercased().hasPrefix(prefix) {
                text = String(raw.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                scope = .folders
                literalPath = nil
                return
            }
            for prefix in ["file ", "f "] where raw.lowercased().hasPrefix(prefix) {
                text = String(raw.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                scope = .dedicated
                literalPath = nil
                return
            }
            text = raw
            scope = .mixed
            literalPath = nil
        }

        /// Open and Reveal for a path that exists, or nil when it does not.
        func literalPathEntries() -> [CommandEntry]? {
            guard let literalPath else { return nil }
            let url = URL(fileURLWithPath: literalPath)
            let name = url.lastPathComponent

            return [
                CommandEntry(
                    item: CatalogItem(
                        id: "file:" + literalPath,
                        title: name,
                        subtitle: literalPath,
                        category: .file,
                        iconPath: literalPath,
                        keys: [],
                        action: .openFile(path: literalPath)
                    ),
                    score: 1_000_000
                ),
                CommandEntry(
                    item: CatalogItem(
                        id: "reveal:" + literalPath,
                        title: "Reveal \(name) in Finder",
                        subtitle: literalPath,
                        category: .command,
                        symbolName: "folder",
                        keys: [],
                        action: .revealInFinder(path: literalPath)
                    ),
                    score: 900_000
                ),
            ]
        }
    }

    /// Scores below this only ever come from the scattered-subsequence tier: every
    /// query letter appears in the name, in order, and nothing more.
    private static let weakTierCeiling = 20_000
    /// A substring hit or better. Something at this level is what the user meant.
    private static let strongTierFloor = 50_000

    /// Drops the long tail once there is a confident answer.
    ///
    /// Typing "wifi" matches "Show Hidden Files" as a subsequence, and listing it
    /// under the Wi-Fi settings pane makes the bar look like it is guessing. When
    /// something matched strongly, the coincidences are worth less than the space
    /// they take, so they go.
    private func pruned(_ entries: [CommandEntry]) -> [CommandEntry] {
        guard entries.contains(where: { $0.score >= Self.strongTierFloor }) else { return entries }
        return entries.filter { $0.score >= Self.weakTierCeiling || $0.category == .file }
    }

    private static func rank(_ lhs: CommandEntry, _ rhs: CommandEntry) -> Bool {
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        if lhs.category.rank != rhs.category.rank { return lhs.category.rank < rhs.category.rank }
        return lhs.title < rhs.title
    }

    /// Empty query: what you have run most, then the app's own tools — the same
    /// bet a launcher makes that you are usually reaching for something familiar.
    private func defaultEntries() -> [CommandEntry] {
        var entries: [CommandEntry] = []
        var used: Set<String> = []

        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for id in history.topIdentifiers(limit: 6) {
            guard let item = byID[id], used.insert(id).inserted else { continue }
            entries.append(CommandEntry(item: item, score: history.boost(for: id)))
        }

        for item in items where item.category == .tool {
            guard used.insert(item.id).inserted else { continue }
            entries.append(CommandEntry(item: item, score: 0))
            if entries.count >= Self.resultLimit { break }
        }
        return entries
    }

    /// Called after something is run, so the ranking learns. Clipboard rows and
    /// calculator answers are deliberately excluded: they are one-offs, and
    /// letting them accumulate frecency would poison the empty-query list.
    func recordUse(_ entry: CommandEntry) {
        switch entry.category {
        case .answer, .clipboard, .file: return
        case .application, .tool, .setting, .command:
            history.record(entry.id)
            Preferences.launchHistory = history
        }
    }

    // MARK: - Maths

    /// Evaluates arithmetic typed into the bar.
    ///
    /// Hand-written rather than `NSExpression` for two reasons, both found by
    /// testing it: `NSExpression(format:)` raises an Objective-C exception on a
    /// partial expression like `"1+"` — which a user types on the way to `"1+2"` —
    /// and Swift's `try?` cannot catch that, so it terminates the process. It also
    /// does integer division, making `10/4` come out as `2`. This parser works in
    /// `Double` throughout and returns nil instead of throwing.
    static func evaluateExpression(_ input: String) -> String? {
        let allowed = CharacterSet(charactersIn: "0123456789.+-*/()%^ ")
        guard input.rangeOfCharacter(from: allowed.inverted) == nil,
              input.rangeOfCharacter(from: CharacterSet(charactersIn: "0123456789")) != nil,
              input.rangeOfCharacter(from: CharacterSet(charactersIn: "+-*/%^")) != nil
        else { return nil }

        var parser = ExpressionParser(input)
        guard let value = parser.parse(), value.isFinite else { return nil }

        // Integral results read better without a trailing ".0"; everything else
        // keeps enough precision to be useful without turning into 0.30000000004.
        if value == value.rounded(), abs(value) < 1e15 {
            return String(Int(value))
        }
        return String(format: "%g", value)
    }
}

/// Recursive-descent parser for the four operations, powers, percent, unary sign
/// and parentheses. Returns nil on anything malformed rather than raising.
private struct ExpressionParser {
    private let characters: [Character]
    private var index = 0

    init(_ input: String) {
        characters = Array(input.filter { !$0.isWhitespace })
    }

    mutating func parse() -> Double? {
        guard let value = parseSum(), index == characters.count else { return nil }
        return value
    }

    private mutating func parseSum() -> Double? {
        guard var result = parseProduct() else { return nil }
        while let op = peek(), op == "+" || op == "-" {
            index += 1
            guard let rhs = parseProduct() else { return nil }
            result = op == "+" ? result + rhs : result - rhs
        }
        return result
    }

    private mutating func parseProduct() -> Double? {
        guard var result = parsePower() else { return nil }
        while let op = peek(), op == "*" || op == "/" || op == "%" {
            index += 1
            guard let rhs = parsePower() else { return nil }
            switch op {
            case "*": result *= rhs
            case "/":
                guard rhs != 0 else { return nil }
                result /= rhs
            default:
                guard rhs != 0 else { return nil }
                result = result.truncatingRemainder(dividingBy: rhs)
            }
        }
        return result
    }

    /// Right-associative, so `2^3^2` is 2^(3^2) as in ordinary notation.
    private mutating func parsePower() -> Double? {
        guard let base = parseUnary() else { return nil }
        guard peek() == "^" else { return base }
        index += 1
        guard let exponent = parsePower() else { return nil }
        return pow(base, exponent)
    }

    private mutating func parseUnary() -> Double? {
        guard let character = peek() else { return nil }
        if character == "-" {
            index += 1
            guard let value = parseUnary() else { return nil }
            return -value
        }
        if character == "+" {
            index += 1
            return parseUnary()
        }
        return parsePrimary()
    }

    private mutating func parsePrimary() -> Double? {
        guard let character = peek() else { return nil }

        if character == "(" {
            index += 1
            guard let value = parseSum(), peek() == ")" else { return nil }
            index += 1
            return value
        }

        var digits = ""
        var sawDot = false
        while let current = peek(), current.isNumber || (current == "." && !sawDot) {
            if current == "." { sawDot = true }
            digits.append(current)
            index += 1
        }
        return digits.isEmpty ? nil : Double(digits)
    }

    private func peek() -> Character? {
        index < characters.count ? characters[index] : nil
    }
}
