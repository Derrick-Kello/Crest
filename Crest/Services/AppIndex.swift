//
//  AppIndex.swift
//  Crest
//

import AppKit
import Foundation

/// Finds every installed application and turns it into a searchable catalog item.
///
/// Everything here runs off the main actor at launch and then never again until
/// something invalidates it, so it can afford to open each bundle's `Info.plist`
/// — which is what makes an app findable by its display name and bundle
/// identifier rather than only by the name of the folder it happens to sit in.
nonisolated enum AppIndex {

    // MARK: - Discovery

    /// The standard application locations, in precedence order. A user-installed
    /// copy wins over a system one, so `/Applications` comes first.
    ///
    /// `/System/Library/CoreServices` is deliberately absent while its
    /// `Applications` subfolder is present: the parent holds a hundred background
    /// agents (WiFiAgent, ScriptMonitor, RegisterPluginIM) that no one opens on
    /// purpose, and indexing them meant typing "wifi" surfaced WiFiAgent instead
    /// of the Wi-Fi settings pane. Filtering on `LSUIElement` instead was tried
    /// and is wrong: it also hides Screenshot, Docker Desktop, and every menu bar
    /// app the user actually installed.
    private static var roots: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "/Applications",
            "\(home)/Applications",
            "/Applications/Utilities",
            "/System/Applications",
            "/System/Applications/Utilities",
            "/System/Library/CoreServices/Applications",
            // Safari and its siblings ship in a Cryptex and are reachable only
            // through a symlink that `contentsOfDirectory` does not follow — so
            // without this root, searching "safari" finds nothing at all.
            "/System/Cryptexes/App/System/Applications",
            "\(home)/Developer/Applications",
            "/Developer/Applications",
            "/Network/Applications",
        ]
    }

    /// Named individually because the directory around them is a hundred
    /// background agents that no one opens on purpose.
    private static let coreServicesAllowList = [
        "Finder", "Screen Time", "Software Update", "Game Center", "VoiceOver",
        "Apple Diagnostics", "Certificate Assistant", "Erase Assistant",
        "Pass Viewer", "Installer", "Setup Assistant", "Accessibility Reader",
        "Memory Slot Utility", "Keychain Circle Notification",
    ]

    static func scan() -> [CatalogItem] {
        // Keyed by lowercased name so an app reachable through two paths — a
        // Cryptex and its symlink, say — produces one row rather than two.
        var seen: Set<String> = []
        var bundles: [(url: URL, root: String)] = []

        for root in roots {
            collect(root: URL(fileURLWithPath: root), depth: 0, origin: root, seen: &seen, into: &bundles)
        }
        // The few things in CoreServices proper that people do open by name.
        // Finder above all: it is the most-used app on the Mac and skipping the
        // directory to avoid the agents would otherwise have skipped it too.
        for name in coreServicesAllowList {
            let url = URL(fileURLWithPath: "/System/Library/CoreServices/\(name).app")
            guard seen.insert(name.lowercased()).inserted,
                  FileManager.default.fileExists(atPath: url.path)
            else { continue }
            bundles.append((url, "/System/Library/CoreServices"))
        }

        return bundles
            .map { item(for: $0.url, root: $0.root) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// `.app` bundles are directories, so the walk has to stop at one rather than
    /// descend into its Contents — hence manual recursion instead of a deep
    /// enumerator, which would wander into every helper app inside every bundle.
    private static func collect(
        root: URL,
        depth: Int,
        origin: String,
        seen: inout Set<String>,
        into result: inout [(url: URL, root: String)]
    ) {
        // Three levels covers vendor folders (Adobe, Microsoft, JetBrains) without
        // turning the scan into a full filesystem walk.
        guard depth <= 3,
              let entries = try? FileManager.default.contentsOfDirectory(
                  at: root,
                  includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                  options: [.skipsHiddenFiles, .skipsPackageDescendants]
              )
        else { return }

        for url in entries {
            if url.pathExtension == "app" {
                let key = url.deletingPathExtension().lastPathComponent.lowercased()
                guard seen.insert(key).inserted else { continue }
                result.append((url, origin))
                continue
            }
            // CoreServices holds hundreds of non-app bundles; descending into them
            // costs more than it finds, so only real directories are followed.
            guard url.pathExtension.isEmpty,
                  (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            else { continue }
            collect(root: url, depth: depth + 1, origin: origin, seen: &seen, into: &result)
        }
    }

    // MARK: - Item construction

    private static func item(for url: URL, root: String) -> CatalogItem {
        let fileName = url.deletingPathExtension().lastPathComponent
        let info = readInfo(at: url)


        // The name shown in Finder is the one people know. It differs from the
        // file name often enough to matter: "Google Chrome" ships as Chrome.app in
        // some builds, and localized installs rename the bundle outright.
        // Some bundles carry a directionality mark in front of the name, which is
        // invisible in Finder but breaks a prefix match on the first real letter.
        let displayName = (info.displayName ?? fileName).strippingFormattingMarks
        let title = displayName

        var aliases: [String] = []
        if displayName.caseInsensitiveCompare(fileName) != .orderedSame {
            aliases.append(fileName)
        }
        aliases.append(contentsOf: Self.aliases(for: displayName))
        aliases.append(contentsOf: Self.aliases(for: fileName))
        // "Visual Studio Code" should answer to "vscode": the name with its spaces
        // removed is what people type when they think of the app as one word.
        let squashed = displayName.replacingOccurrences(of: " ", with: "")
        if squashed.count != displayName.count { aliases.append(squashed) }

        var weak: [String] = []
        if let bundleID = info.bundleID { weak.append(bundleID) }
        // The containing folder, so "adobe" finds everything filed under Adobe.
        let parent = url.deletingLastPathComponent().lastPathComponent
        if parent != "Applications" && parent != "Utilities" { weak.append(parent) }

        return CatalogItem(
            id: "app:" + url.path,
            title: title,
            subtitle: subtitle(for: url, root: root),
            category: .application,
            iconPath: url.path,
            keys: CatalogItem.keys(title: title, aliases: uniqued(aliases), weak: uniqued(weak)),
            action: .launchApp(path: url.path)
        )
    }

    /// Vendor-foldered apps are ambiguous by name alone, so the subtitle carries
    /// the containing folder rather than a flat "Application" for everything.
    private static func subtitle(for url: URL, root: String) -> String {
        let parent = url.deletingLastPathComponent()
        if parent.path == root { return "Application" }
        return "Application — \(parent.lastPathComponent)"
    }

    private struct BundleInfo {
        var displayName: String?
        var bundleID: String?
    }

    /// Reads the two fields worth having straight from the plist.
    ///
    /// `Bundle(url:)` would give the same answers, but it caches every bundle it
    /// touches for the process lifetime — several hundred of them during a scan —
    /// and none of that is ever needed again.
    private static func readInfo(at url: URL) -> BundleInfo {
        let plist = url.appending(path: "Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let raw = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dictionary = raw as? [String: Any]
        else { return BundleInfo() }

        // `CFBundleDisplayName` is the user-facing one; `CFBundleName` is the
        // short form and is a reasonable second choice when the first is absent.
        let display = (dictionary["CFBundleDisplayName"] as? String)
            ?? (dictionary["CFBundleName"] as? String)

        return BundleInfo(
            displayName: display?.trimmingCharacters(in: .whitespaces).nilIfEmpty,
            bundleID: dictionary["CFBundleIdentifier"] as? String
        )
    }

    private static func uniqued(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    // MARK: - Aliases

    /// Names people type that no amount of fuzzy matching would connect to the
    /// real one. "vsc" reaches Visual Studio Code through initials; "editor" only
    /// reaches it because it is written down here.
    private static func aliases(for name: String) -> [String] {
        Self.aliasTable[name.lowercased()] ?? []
    }

    private static let aliasTable: [String: [String]] = [
        "visual studio code": ["vscode", "vs code", "code", "editor"],
        "code": ["vscode", "visual studio code"],
        "vscodium": ["vscode", "codium"],
        "cursor": ["editor", "cursor editor"],
        "xcode": ["ide", "swift"],
        "activity monitor": ["task manager", "processes", "cpu", "ram", "memory"],
        "system settings": ["preferences", "system preferences", "settings", "prefs"],
        "system preferences": ["settings", "system settings", "prefs"],
        "terminal": ["shell", "console", "bash", "zsh", "cli"],
        "iterm": ["terminal", "shell", "console"],
        "iterm2": ["terminal", "shell", "console"],
        "warp": ["terminal", "shell"],
        "ghostty": ["terminal", "shell"],
        "finder": ["files", "file manager", "explorer"],
        "safari": ["browser", "web"],
        "google chrome": ["browser", "chrome", "web"],
        "firefox": ["browser", "web"],
        "brave browser": ["browser", "brave", "web"],
        "arc": ["browser", "web"],
        "microsoft edge": ["browser", "edge", "web"],
        "mail": ["email", "e-mail", "inbox"],
        "messages": ["imessage", "sms", "chat", "texts"],
        "facetime": ["video call", "call"],
        "photos": ["images", "pictures", "library"],
        "preview": ["pdf", "image viewer", "viewer"],
        "quicktime player": ["video", "screen recording", "player"],
        "music": ["itunes", "songs", "audio", "player"],
        "disk utility": ["format", "partition", "erase", "raid", "first aid"],
        "keychain access": ["passwords", "certificates", "keys", "credentials"],
        "screenshot": ["screen capture", "grab", "screen shot"],
        "screen sharing": ["vnc", "remote desktop"],
        "font book": ["fonts", "typeface"],
        "console": ["logs", "syslog", "system log"],
        "migration assistant": ["transfer", "migrate"],
        "time machine": ["backup", "restore", "snapshots"],
        "app store": ["store", "apps", "updates"],
        "calculator": ["calc", "maths", "math"],
        "notes": ["notepad", "scratchpad"],
        "reminders": ["todo", "tasks", "to do"],
        "calendar": ["ical", "events", "schedule"],
        "contacts": ["address book", "people"],
        "voice memos": ["recorder", "audio recording"],
        "docker desktop": ["docker", "containers"],
        "docker": ["containers"],
        "postman": ["api", "http client", "rest"],
        "figma": ["design", "ui"],
        "slack": ["chat", "messaging", "work"],
        "discord": ["chat", "voice", "gaming"],
        "zoom.us": ["zoom", "meeting", "video call"],
        "microsoft teams": ["teams", "meeting", "chat"],
        "notion": ["notes", "wiki", "docs"],
        "obsidian": ["notes", "markdown", "vault"],
        "spotify": ["music", "podcasts", "audio"],
        "vlc": ["video", "player", "media"],
        "iina": ["video", "player", "media"],
        "the unarchiver": ["zip", "unzip", "extract", "archive"],
        "keka": ["zip", "unzip", "extract", "archive"],
        "android studio": ["ide", "android", "kotlin"],
        "intellij idea": ["ide", "java", "jetbrains"],
        "pycharm": ["ide", "python", "jetbrains"],
        "webstorm": ["ide", "javascript", "jetbrains"],
        "sublime text": ["editor", "sublime"],
        "tableplus": ["database", "sql", "db"],
        "sequel ace": ["database", "mysql", "sql"],
        "transmit": ["ftp", "sftp", "transfer"],
        "cyberduck": ["ftp", "sftp", "s3"],
        "1password": ["passwords", "vault", "secrets"],
        "bitwarden": ["passwords", "vault", "secrets"],
        "adobe acrobat": ["pdf", "acrobat", "reader"],
        "adobe photoshop": ["photoshop", "ps", "image editor"],
        "adobe illustrator": ["illustrator", "ai", "vector"],
        "microsoft word": ["word", "doc", "docx", "writer"],
        "microsoft excel": ["excel", "xls", "xlsx", "spreadsheet"],
        "microsoft powerpoint": ["powerpoint", "ppt", "slides"],
        "numbers": ["spreadsheet", "excel"],
        "pages": ["word processor", "document"],
        "keynote": ["slides", "presentation", "powerpoint"],
    ]
}

private nonisolated extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }

    /// Drops zero-width and bidirectional marks. `‎WhatsApp` ships with a
    /// left-to-right mark in front of the W, so typing "w" matched nothing.
    var strippingFormattingMarks: String {
        filter { !$0.unicodeScalars.allSatisfy { scalar in
            scalar.properties.isDefaultIgnorableCodePoint || scalar.properties.isBidiControl
        } }
    }
}

/// Launch history, so the things you actually run float to the top.
///
/// Frequency alone entrenches whatever you opened most last month; recency alone
/// forgets your daily tools. Combining them — the usual "frecency" — keeps the
/// ranking responsive without thrashing.
struct LaunchHistory: Codable, Sendable {
    private var counts: [String: Int] = [:]
    private var lastUsed: [String: Date] = [:]

    mutating func record(_ id: String) {
        counts[id, default: 0] += 1
        lastUsed[id] = Date()
        // Bounded so a long-lived install cannot grow the stored history without
        // limit; the entries dropped are the ones no ranking would have surfaced.
        if counts.count > 500 { prune() }
    }

    func boost(for id: String) -> Int {
        guard let count = counts[id] else { return 0 }
        let frequency = min(count, 25) * 60

        guard let last = lastUsed[id] else { return frequency }
        let days = Date().timeIntervalSince(last) / 86_400
        let recency: Int
        switch days {
        case ..<1: recency = 1_200
        case ..<7: recency = 700
        case ..<30: recency = 300
        default: recency = 0
        }
        return frequency + recency
    }

    /// Most-used entries, for the empty-query state.
    func topIdentifiers(limit: Int) -> [String] {
        counts.keys
            .sorted { boost(for: $0) > boost(for: $1) }
            .prefix(limit)
            .map { $0 }
    }

    private mutating func prune() {
        let keep = Set(counts.keys.sorted { boost(for: $0) > boost(for: $1) }.prefix(250))
        counts = counts.filter { keep.contains($0.key) }
        lastUsed = lastUsed.filter { keep.contains($0.key) }
    }
}
