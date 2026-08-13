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
/// The app list is the only expensive part, so it is gathered once on a background
/// task and cached; typing then filters an in-memory array and never touches disk.
@MainActor
@Observable
final class CommandBarService {
    static let shared = CommandBarService()

    private(set) var apps: [InstalledApp] = []
    private var hasLoadedApps = false

    struct InstalledApp: Sendable {
        let name: String
        let path: String
        let lowercaseName: String
    }

    private init() {}

    func loadAppsIfNeeded() async {
        guard !hasLoadedApps else { return }
        hasLoadedApps = true
        apps = await Self.scanApps()
    }

    /// Refreshes the cache — apps get installed while the app is running.
    func reloadApps() async {
        apps = await Self.scanApps()
    }

    private static func scanApps() async -> [InstalledApp] {
        await Task.detached(priority: .utility) {
            let roots = [
                "/Applications",
                "/System/Applications",
                "/System/Applications/Utilities",
                "/Applications/Utilities",
                FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications").path,
            ]
            var found: [String: InstalledApp] = [:]

            for root in roots {
                guard let entries = try? FileManager.default.contentsOfDirectory(
                    at: URL(fileURLWithPath: root),
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                ) else { continue }

                for url in entries where url.pathExtension == "app" {
                    let name = url.deletingPathExtension().lastPathComponent
                    // Keyed by name so the same app in two roots appears once.
                    found[name] = InstalledApp(name: name, path: url.path, lowercaseName: name.lowercased())
                }
            }
            return found.values.sorted { $0.name < $1.name }
        }.value
    }

    // MARK: - Search

    func results(for query: String) -> [CommandEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return defaultEntries() }

        var entries: [CommandEntry] = []

        if let answer = Self.evaluateExpression(trimmed) {
            entries.append(CommandEntry(
                id: "math", title: answer, subtitle: "\(trimmed) — press ↩ to copy",
                kind: .math, score: 10_000
            ))
        }

        let needle = trimmed.lowercased()

        for app in apps {
            guard let score = Self.fuzzyScore(needle: needle, haystack: app.lowercaseName) else { continue }
            entries.append(CommandEntry(
                id: "app:" + app.path, title: app.name, subtitle: "Application",
                kind: .app, iconPath: app.path, score: score
            ))
        }

        for action in Self.actions {
            guard let score = Self.fuzzyScore(needle: needle, haystack: action.title.lowercased()) else { continue }
            entries.append(CommandEntry(
                id: action.id, title: action.title, subtitle: action.subtitle,
                kind: .action, score: score + 200
            ))
        }

        for entry in ClipboardService.shared.entries.prefix(40) {
            guard let score = Self.fuzzyScore(needle: needle, haystack: entry.preview.lowercased()) else { continue }
            entries.append(CommandEntry(
                id: "clip:" + entry.id.uuidString, title: entry.preview,
                subtitle: "Clipboard — press ↩ to copy", kind: .clipboard, score: score
            ))
        }

        return entries
            .sorted {
                $0.score != $1.score
                    ? $0.score > $1.score
                    : ($0.kind.priority != $1.kind.priority
                        ? $0.kind.priority < $1.kind.priority
                        : $0.title < $1.title)
            }
            .prefix(12)
            .map { $0 }
    }

    private func defaultEntries() -> [CommandEntry] {
        Self.actions.map {
            CommandEntry(id: $0.id, title: $0.title, subtitle: $0.subtitle, kind: .action)
        }
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
        Action(id: "action:color", title: "Pick a colour", subtitle: "Sample a colour from the screen"),
        Action(id: "action:clipboard", title: "Clipboard history", subtitle: "Show recent copies"),
        Action(id: "action:emptytrash", title: "Open Trash", subtitle: "Reveal the Trash in Finder"),
    ]

    // MARK: - Matching

    /// Subsequence match with a bonus for consecutive hits and word starts, so
    /// "ac" ranks Activity Monitor above Mail (m-a-i-**l**… no) and "sysp" finds
    /// System Preferences. Returns nil when the needle isn't a subsequence at all.
    static func fuzzyScore(needle: String, haystack: String) -> Int? {
        guard !needle.isEmpty else { return 0 }
        if haystack == needle { return 1_000 }
        if haystack.hasPrefix(needle) { return 800 + max(0, 100 - haystack.count) }

        var score = 0
        var streak = 0
        var haystackIndex = haystack.startIndex
        var previousWasSeparator = true

        for character in needle {
            var matched = false
            while haystackIndex < haystack.endIndex {
                let current = haystack[haystackIndex]
                haystackIndex = haystack.index(after: haystackIndex)
                if current == character {
                    streak += 1
                    score += 10 + streak * 2 + (previousWasSeparator ? 15 : 0)
                    previousWasSeparator = false
                    matched = true
                    break
                }
                streak = 0
                previousWasSeparator = current == " " || current == "-" || current == "_"
            }
            guard matched else { return nil }
        }
        return score
    }

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
