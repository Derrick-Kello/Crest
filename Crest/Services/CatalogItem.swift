//
//  CatalogItem.swift
//  Crest
//

import Foundation

/// What kind of thing a result is. Drives the section header it appears under,
/// the fallback glyph, and how ties are broken between equally-scored results.
nonisolated enum CommandCategory: String, Sendable, CaseIterable, Codable {
    case answer
    case application
    case tool
    case setting
    case command
    case file
    case clipboard

    /// Section header in the result list. Raycast groups rather than interleaving,
    /// and grouping is what makes a long list scannable instead of a soup.
    var title: String {
        switch self {
        case .answer: "Result"
        case .application: "Applications"
        case .tool: "Crest"
        case .setting: "System Settings"
        case .command: "System Commands"
        case .file: "Files"
        case .clipboard: "Clipboard History"
        }
    }

    var symbolName: String {
        switch self {
        case .answer: "equal.square"
        case .application: "app"
        case .tool: "wrench.and.screwdriver"
        case .setting: "gearshape"
        case .command: "terminal"
        case .file: "doc"
        case .clipboard: "doc.on.clipboard"
        }
    }

    /// Order the sections appear in, and the tiebreak when two results score the
    /// same. An answer the user could only have got from the calculator outranks a
    /// fuzzy app match; files come last because they are the noisiest source.
    var rank: Int {
        switch self {
        case .answer: 0
        case .application: 1
        case .tool: 2
        case .command: 3
        case .setting: 4
        case .clipboard: 5
        case .file: 6
        }
    }
}

/// What running a result does. Keeping this on the item rather than parsing the
/// identifier at execution time means a new catalog entry is one line in one file
/// instead of an entry here and a matching `case` in a switch somewhere else.
nonisolated enum CommandAction: Sendable, Hashable {
    case launchApp(path: String)
    case openFile(path: String)
    case revealInFinder(path: String)
    case openURL(String)
    /// Routed back into the view model — the in-app tools and panel sections.
    case appAction(String)
    case copyText(String)
    /// A shell one-liner for the system commands. Always a literal from
    /// `SystemCommands`; nothing the user types is ever interpolated into one.
    case shell(String)
    case appleScript(String)
}

/// One searchable thing in the catalog.
nonisolated struct CatalogItem: Sendable, Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let category: CommandCategory
    /// A file path whose real icon should be drawn instead of the fallback glyph.
    let iconPath: String?
    /// SF Symbol used when there is no icon path; falls back to the category's.
    let symbolName: String?
    let keys: [MatchKey]
    let action: CommandAction

    init(
        id: String,
        title: String,
        subtitle: String,
        category: CommandCategory,
        iconPath: String? = nil,
        symbolName: String? = nil,
        keys: [MatchKey],
        action: CommandAction
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.category = category
        self.iconPath = iconPath
        self.symbolName = symbolName
        self.keys = keys
        self.action = action
    }

    /// The path this item points at, when it has one. Callers that need to act on
    /// a file — showing an icon, reading a bundle — should go through this rather
    /// than assume `iconPath` is always the target.
    var filePath: String? {
        switch action {
        case .launchApp(let path), .openFile(let path), .revealInFinder(let path): path
        default: nil
        }
    }

    /// Builds the usual key set: the title at full weight, then aliases slightly
    /// below it, so an alias hit never beats someone typing another item's name.
    static func keys(title: String, aliases: [String] = [], weak: [String] = []) -> [MatchKey] {
        var keys = [MatchKey(title, weight: 100)]
        keys.append(contentsOf: aliases.map { MatchKey($0, weight: 88) })
        keys.append(contentsOf: weak.map { MatchKey($0, weight: 55) })
        return keys
    }
}

/// A scored item, ready to display.
nonisolated struct CommandEntry: Identifiable, Sendable, Hashable {
    let item: CatalogItem
    let score: Int

    var id: String { item.id }
    var title: String { item.title }
    var subtitle: String { item.subtitle }
    var category: CommandCategory { item.category }
    var iconPath: String? { item.iconPath }
    var action: CommandAction { item.action }

    var symbolName: String { item.symbolName ?? item.category.symbolName }
}
