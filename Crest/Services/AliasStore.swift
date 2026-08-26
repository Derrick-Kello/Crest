//
//  AliasStore.swift
//  Crest
//

import Foundation

/// The names the user has taught the command bar.
///
/// The built-in alias table in `AppIndex` covers what most people call things;
/// this covers what *you* call them. Typing "t" for Terminal or "db" for
/// TablePlus is the difference between a launcher you adapt to and one that
/// adapts to you, and it is one line of storage rather than a second index.
///
/// An alias is matched as an exact word, not fuzzily. That is deliberate: a
/// one- or two-letter alias would fuzzy-match half the catalog, and the whole
/// point of assigning one is that it lands on exactly the thing you meant.
@MainActor
@Observable
final class AliasStore {
    static let shared = AliasStore()

    /// Catalog item id → the aliases assigned to it.
    private(set) var aliases: [String: [String]] = [:]
    /// Bumped on every change so an open command bar re-runs its query.
    private(set) var generation = 0

    /// Reverse lookup, rebuilt on write rather than on every keystroke: the
    /// command bar consults it once per character typed and the table only
    /// changes when someone edits it in Settings.
    private var byAlias: [String: String] = [:]

    private init() {
        aliases = Preferences.commandAliases
        rebuildIndex()
    }

    // MARK: - Lookup

    /// The item `text` is an alias for, if any. Case- and whitespace-insensitive,
    /// because "VS" and "vs " are the same instruction.
    func identifier(matching text: String) -> String? {
        byAlias[Self.normalize(text)]
    }

    /// Extra match keys for an item, weighted above its own name so an assigned
    /// alias wins the tie against a coincidental substring hit elsewhere.
    func matchKeys(for identifier: String) -> [MatchKey] {
        guard let list = aliases[identifier] else { return [] }
        return list.map { MatchKey($0, weight: 100) }
    }

    func aliasList(for identifier: String) -> [String] {
        aliases[identifier] ?? []
    }

    /// Rows for the settings table, newest binding last, sorted by display name.
    func entries(resolving name: (String) -> String?) -> [AliasEntry] {
        aliases.compactMap { identifier, list in
            guard !list.isEmpty else { return nil }
            return AliasEntry(
                identifier: identifier,
                title: name(identifier) ?? Self.fallbackTitle(for: identifier),
                aliases: list
            )
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    // MARK: - Editing

    /// Replaces every alias on `identifier`. An empty list removes the entry.
    ///
    /// An alias already pointing somewhere else is moved rather than duplicated:
    /// two items answering to "db" would make the shorter name useless, and
    /// silently keeping the older binding is the more surprising of the two.
    func setAliases(_ raw: String, for identifier: String) {
        let parsed = Self.parse(raw)
        guard !parsed.isEmpty else {
            aliases.removeValue(forKey: identifier)
            commit()
            return
        }

        let claimed = Set(parsed.map(Self.normalize))
        for (owner, list) in aliases where owner != identifier {
            let kept = list.filter { !claimed.contains(Self.normalize($0)) }
            if kept.count != list.count {
                if kept.isEmpty { aliases.removeValue(forKey: owner) } else { aliases[owner] = kept }
            }
        }

        aliases[identifier] = parsed
        commit()
    }

    func remove(_ identifier: String) {
        aliases.removeValue(forKey: identifier)
        commit()
    }

    /// Drops aliases pointing at items that no longer exist — an uninstalled app,
    /// a settings pane a macOS update removed. Called after a reindex, so a stale
    /// row does not sit in Settings forever claiming a shortcut nothing answers.
    func prune(keeping identifiers: Set<String>) {
        // File and clipboard rows are transient by nature and never in the
        // catalog, so they are not evidence of anything having gone missing.
        let stale = aliases.keys.filter {
            !identifiers.contains($0) && !$0.hasPrefix("file:") && !$0.hasPrefix("clip:")
        }
        guard !stale.isEmpty else { return }
        for identifier in stale { aliases.removeValue(forKey: identifier) }
        commit()
    }

    private func commit() {
        Preferences.commandAliases = aliases
        rebuildIndex()
        generation += 1
    }

    private func rebuildIndex() {
        byAlias = [:]
        for (identifier, list) in aliases {
            for alias in list { byAlias[Self.normalize(alias)] = identifier }
        }
    }

    // MARK: - Parsing

    /// Comma- or space-separated, deduplicated, with the empties dropped, so the
    /// field accepts "vs, code" and "vs code" as the same two aliases.
    static func parse(_ raw: String) -> [String] {
        var seen: Set<String> = []
        return raw
            .split(whereSeparator: { $0 == "," || $0.isWhitespace })
            .map { String($0) }
            .filter { !$0.isEmpty && seen.insert(normalize($0)).inserted }
    }

    static func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func fallbackTitle(for identifier: String) -> String {
        if identifier.hasPrefix("app:") {
            return URL(fileURLWithPath: String(identifier.dropFirst(4)))
                .deletingPathExtension().lastPathComponent
        }
        return identifier
    }
}

/// One row of the alias table.
struct AliasEntry: Identifiable, Hashable {
    let identifier: String
    let title: String
    let aliases: [String]

    var id: String { identifier }
    var joined: String { aliases.joined(separator: ", ") }
}
