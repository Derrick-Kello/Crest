//
//  BrewParsing.swift
//  DiskPilot
//

import Foundation

/// Turns `brew`'s output into values. Kept apart from the service so the parsing
/// is pure, testable, and free of any actor.
enum BrewJSON {

    // MARK: - Package list

    /// Decodes `brew info --json=v2`. The same shape serves the installed list and
    /// a search's detail lookup — the only difference is whether a package with no
    /// installed version is kept.
    static func parseInstalled(_ data: Data, includeUninstalled: Bool = false) -> [BrewPackage] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        var packages: [BrewPackage] = []

        for entry in root["formulae"] as? [[String: Any]] ?? [] {
            guard let name = entry["name"] as? String else { continue }
            // `installed` is an array of builds; the last one is the live version.
            let installedVersion = (entry["installed"] as? [[String: Any]])?.last?["version"] as? String
            guard installedVersion != nil || includeUninstalled else { continue }
            let stable = (entry["versions"] as? [String: Any])?["stable"] as? String ?? "—"
            packages.append(BrewPackage(
                name: name,
                isCask: false,
                summary: entry["desc"] as? String ?? "",
                tap: entry["tap"] as? String ?? "",
                installedVersion: installedVersion,
                latestVersion: stable,
                isOutdated: entry["outdated"] as? Bool ?? false,
                isPinned: entry["pinned"] as? Bool ?? false
            ))
        }

        for entry in root["casks"] as? [[String: Any]] ?? [] {
            guard let token = entry["token"] as? String else { continue }
            let installedVersion = entry["installed"] as? String
            guard installedVersion != nil || includeUninstalled else { continue }
            // A cask's `name` is a list of display names; the token is what every
            // brew command actually takes, so it stays the identity.
            let display = (entry["name"] as? [String])?.first ?? token
            packages.append(BrewPackage(
                name: token,
                isCask: true,
                summary: entry["desc"] as? String ?? display,
                tap: entry["tap"] as? String ?? "",
                installedVersion: installedVersion,
                latestVersion: entry["version"] as? String ?? "—",
                isOutdated: entry["outdated"] as? Bool ?? false,
                isPinned: false
            ))
        }

        return packages.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Search

    /// `brew search` prints one name per line when its output isn't a terminal,
    /// with occasional advisory lines that are not packages.
    static func parseSearch(formula: String, cask: String) -> (formulae: [String], casks: [String]) {
        (names(in: formula), names(in: cask))
    }

    private static func names(in output: String) -> [String] {
        output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { line in
                !line.isEmpty
                    && !line.hasPrefix("==>")
                    && !line.hasPrefix("If you meant")
                    && !line.hasPrefix("Warning")
                    && !line.hasPrefix("Error")
                    && HomebrewService.isSafeName(line)
            }
    }

    // MARK: - Cleanup estimate

    /// Reads "This operation would free approximately 72.3MB of disk space." No
    /// machine-readable form of this exists, so the sentence is the interface.
    static func parseFreeableBytes(_ output: String) -> UInt64 {
        guard let range = output.range(
            of: #"would free approximately ([0-9]+(?:\.[0-9]+)?)\s?([KMGT]?B)"#,
            options: .regularExpression
        ) else { return 0 }

        let sentence = String(output[range])
        guard let numberRange = sentence.range(of: #"[0-9]+(?:\.[0-9]+)?"#, options: .regularExpression),
              let value = Double(sentence[numberRange]),
              let unitRange = sentence.range(of: #"[KMGT]?B$"#, options: .regularExpression)
        else { return 0 }

        let multiplier: Double
        switch sentence[unitRange] {
        case "KB": multiplier = 1_000
        case "MB": multiplier = 1_000_000
        case "GB": multiplier = 1_000_000_000
        case "TB": multiplier = 1_000_000_000_000
        default: multiplier = 1
        }
        return UInt64(value * multiplier)
    }
}

/// Reads a live `brew` stream and reports what changed.
///
/// Homebrew's progress is a mixture of headline lines (`==> Downloading …`) and
/// `curl`'s own progress bar, which repaints the same line with carriage returns
/// and ANSI escapes. Feeding that straight into a label makes it flicker through
/// half-drawn bar characters, so this keeps only the last complete line and the
/// most recent percentage.
final class BrewProgressParser: @unchecked Sendable {
    struct Update {
        var phase: BrewPhase?
        var fraction: Double?
        var line: String?
    }

    private let lock = NSLock()
    private var carry = ""

    func consume(_ chunk: String) -> Update? {
        lock.lock()
        carry += chunk
        // Split on both newline kinds: curl's redraws are carriage returns only.
        let pieces = carry.components(separatedBy: CharacterSet(charactersIn: "\n\r"))
        carry = pieces.last ?? ""
        let complete = pieces.dropLast()
        lock.unlock()

        var update = Update()
        var sawSomething = false

        for raw in complete {
            let line = Self.strip(raw)
            guard !line.isEmpty else { continue }
            sawSomething = true

            if let percent = Self.percentage(in: line) {
                update.fraction = percent
            }
            if let phase = Self.phase(for: line) {
                update.phase = phase
            }
            // Progress-bar remnants make a useless caption; keep real sentences.
            if line.rangeOfCharacter(from: Self.readableCharacters) != nil, line.count > 3 {
                update.line = String(line.prefix(120))
            }
        }

        return sawSomething ? update : nil
    }

    private static let readableCharacters = CharacterSet.letters

    /// Drops ANSI colour and cursor escapes so they never reach a SwiftUI `Text`.
    static func strip(_ line: String) -> String {
        line
            // ICU spells an escape `\uHHHH`; the Swift `\u{1B}` form is not a
            // regex escape and would match a literal "u{1B}" instead.
            .replacingOccurrences(of: #"\u001B\[[0-9;?]*[ -/]*[@-~]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    static func percentage(in line: String) -> Double? {
        guard let range = line.range(of: #"([0-9]{1,3}(?:\.[0-9]+)?)%"#, options: .regularExpression) else { return nil }
        let text = line[range].dropLast()
        guard let value = Double(text) else { return nil }
        return min(max(value / 100, 0), 1)
    }

    static func phase(for line: String) -> BrewPhase? {
        let lowered = line.lowercased()
        if lowered.contains("downloading") || lowered.contains("fetching") { return .downloading }
        if lowered.contains("installing") || lowered.contains("pouring") || lowered.contains("linking") { return .installing }
        if lowered.contains("uninstalling") || lowered.contains("removing") || lowered.contains("purging") { return .removing }
        if lowered.contains("upgrading") { return .updating }
        if lowered.contains("updating") || lowered.contains("tapped") { return .refreshing }
        return nil
    }
}
