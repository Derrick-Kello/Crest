//
//  CommandBarService.swift
//  DiskPilot
//

import AppKit
import Foundation

enum CommandKind: String, Sendable {
    case app, action, math, clipboard, color

    var iconName: String {
        switch self {
        case .app: "app"
        case .action: "bolt"
        case .math: "function"
        case .clipboard: "doc.on.clipboard"
        case .color: "eyedropper"
        }
    }

    /// Sort weight when scores tie. A calculated answer should outrank a fuzzy app
    /// match, because the user typed something only the calculator could parse.
    var priority: Int {
        switch self {
        case .math: 0
        case .action: 1
        case .app: 2
        case .clipboard: 3
        case .color: 4
        }
    }
}

struct CommandEntry: Identifiable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let kind: CommandKind
    /// Set for apps so the row can show the real icon instead of a glyph.
    let iconPath: String?
    let score: Int

    init(id: String, title: String, subtitle: String, kind: CommandKind, iconPath: String? = nil, score: Int = 0) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.kind = kind
        self.iconPath = iconPath
        self.score = score
    }
}

/// Builds and searches the command bar catalog.
///
/// The index is built once in the background at app launch — not on first open,
/// which used to mean the very first search returned nothing at all — and every
/// keystroke afterwards is pure in-memory matching.
@MainActor
@Observable
final class CommandBarService {
    static let shared = CommandBarService()

    private(set) var apps: [IndexedApp] = []
    /// Bumped whenever the index changes so the view can re-run its query; the
    /// results used to be computed once and never refreshed when the scan landed.
    private(set) var indexGeneration = 0
    private(set) var isIndexing = false

    private var history = Preferences.launchHistory
    private var iconCache: [String: NSImage] = [:]
    private var indexTask: Task<Void, Never>?

    private init() {}

    // MARK: - Index

    /// Safe to call repeatedly; the scan runs once unless `force` is set.
    func buildIndex(force: Bool = false) {
        if !force, !apps.isEmpty || isIndexing { return }
        indexTask?.cancel()
        isIndexing = true

        indexTask = Task { [weak self] in
            let scanned = await Task.detached(priority: .userInitiated) { AppIndex.scan() }.value
            guard !Task.isCancelled, let self else { return }
            self.apps = scanned
            self.iconCache.removeAll()
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
        // Bounded: an index of a few hundred apps is fine, but never unbounded.
        if iconCache.count > 400 { iconCache.removeAll() }
        iconCache[path] = icon
        return icon
    }

    // MARK: - Search

    func results(for query: String) -> [CommandEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return defaultEntries() }

        let needle = trimmed.lowercased()
        var entries: [CommandEntry] = []

        if let answer = Self.evaluateExpression(trimmed) {
            entries.append(CommandEntry(
                id: "math", title: answer, subtitle: "\(trimmed) — press ↩ to copy",
                kind: .math, score: 100_000
            ))
        }

        for app in apps {
            guard let base = AppIndex.score(
                query: needle, candidate: app.lowercaseName, initials: app.initials
            ) else { continue }
            entries.append(CommandEntry(
                id: "app:" + app.path,
                title: app.name,
                subtitle: subtitle(for: app),
                kind: .app,
                iconPath: app.path,
                score: base + history.boost(for: "app:" + app.path)
            ))
        }

        for action in Self.actions {
            guard let base = AppIndex.score(
                query: needle,
                candidate: action.title.lowercased(),
                initials: AppIndex.initials(of: action.title)
            ) else { continue }
            entries.append(CommandEntry(
                id: action.id, title: action.title, subtitle: action.subtitle,
                kind: .action, score: base + 400 + history.boost(for: action.id)
            ))
        }

        for entry in ClipboardService.shared.entries.prefix(40) {
            let preview = entry.preview.lowercased()
            guard let base = AppIndex.score(query: needle, candidate: preview, initials: "") else { continue }
            entries.append(CommandEntry(
                id: "clip:" + entry.id.uuidString, title: entry.preview,
                subtitle: "Clipboard — press ↩ to copy", kind: .clipboard,
                score: base / 2
            ))
        }

        return Array(entries.sorted(by: Self.rank).prefix(12))
    }

    /// Vendor-foldered apps are ambiguous by name alone, so the subtitle carries
    /// the containing folder rather than a flat "Application" for everything.
    private func subtitle(for app: IndexedApp) -> String {
        let parent = URL(fileURLWithPath: app.path).deletingLastPathComponent()
        let folder = parent.lastPathComponent
        return folder == "Applications" ? "Application" : "Application — \(folder)"
    }

    private static func rank(_ lhs: CommandEntry, _ rhs: CommandEntry) -> Bool {
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        if lhs.kind.priority != rhs.kind.priority { return lhs.kind.priority < rhs.kind.priority }
        return lhs.title < rhs.title
    }

    /// Empty query: the apps you launch most, then the built-in actions — the same
    /// bet a launcher makes that you are usually reaching for something familiar.
    private func defaultEntries() -> [CommandEntry] {
        var entries: [CommandEntry] = []

        let frequentIDs = history.topIdentifiers(limit: 5)
        for id in frequentIDs where id.hasPrefix("app:") {
            let path = String(id.dropFirst(4))
            guard let app = apps.first(where: { $0.path == path }) else { continue }
            entries.append(CommandEntry(
                id: id, title: app.name, subtitle: "Recent", kind: .app,
                iconPath: app.path, score: history.boost(for: id)
            ))
        }

        entries.append(contentsOf: Self.actions.map {
            CommandEntry(id: $0.id, title: $0.title, subtitle: $0.subtitle, kind: .action)
        })
        return entries
    }

    /// Called after something is run, so the ranking learns.
    func recordUse(_ entry: CommandEntry) {
        guard entry.kind == .app || entry.kind == .action else { return }
        history.record(entry.id)
        Preferences.launchHistory = history
    }

    struct Action: Sendable {
        let id: String
        let title: String
        let subtitle: String
    }

    static let actions: [Action] = [
        Action(id: "action:scan", title: "Scan for junk", subtitle: "Run the cleaner"),
        Action(id: "action:review", title: "Review cleanable items", subtitle: "Open the review window"),
        Action(id: "action:keepawake", title: "Toggle Keep Awake", subtitle: "Prevent or allow sleep"),
        Action(id: "action:color", title: "Pick a color", subtitle: "Sample a color from the screen"),
        Action(id: "action:clipboard", title: "Clipboard history", subtitle: "Show recent copies"),
        Action(id: "action:emptytrash", title: "Open Trash", subtitle: "Reveal the Trash in Finder"),
        Action(id: "action:uninstall", title: "Uninstall an app", subtitle: "Remove an app and its leftovers"),
        Action(id: "action:network", title: "Network activity", subtitle: "Live speed and which apps are using it"),
        Action(id: "action:brewupdate", title: "Update Homebrew packages", subtitle: "Runs brew upgrade"),
        Action(id: "action:brewcleanup", title: "Reclaim Homebrew space", subtitle: "Runs brew cleanup"),
    ]

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
