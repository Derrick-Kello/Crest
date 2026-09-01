//
//  FileRanking.swift
//  Crest
//

import Foundation

/// Decides which of Spotlight's answers are worth showing, and in what order.
///
/// Spotlight matches a name anywhere in the string and sorts by last-used date,
/// and on a developer's Mac that combination is close to useless: searching
/// "desk" returned 790 hits, of which the first six were `~/Desktop` and five
/// object files out of a Rust build directory, because a `.o` file has no
/// last-used date and neither does anything else, so the order after the first
/// row was whatever Spotlight felt like. Every folder below the first one was
/// past the cut. Hence a second opinion, formed here.
///
/// Pure, and separate from the query that feeds it, so the rules can be checked
/// against real paths in `Tests/run.sh` rather than by typing into the bar and
/// squinting.
nonisolated enum FileRanking {

    struct Candidate: Sendable, Equatable {
        let path: String
        let name: String
        let isFolder: Bool
        var lastUsed: Date?

        init(path: String, name: String, isFolder: Bool, lastUsed: Date? = nil) {
            self.path = path
            self.name = name
            self.isFolder = isFolder
            self.lastUsed = lastUsed
        }
    }

    /// A rank from the path alone, or nil when the path should never be shown.
    ///
    /// The cheap half, and the reason the search is fast. A result's path is
    /// already in memory once Spotlight has gathered — measured at a millisecond
    /// for four hundred of them — while every other attribute is a round trip to
    /// the metadata store at about a millisecond *each*. Reading four attributes
    /// per result to rank four hundred of them took 377ms on the main actor,
    /// which is a third of a second of frozen command bar per keystroke.
    ///
    /// So the path decides who is still in the running, and only the survivors
    /// are worth asking the filesystem about.
    static func provisionalScore(path: String, query: String) -> Int? {
        guard !isNoise(path: path) else { return nil }
        let name = (path as NSString).lastPathComponent
        return nameScore(name, query: query) - depthPenalty(path) - supportPenalty(path)
    }

    /// The final rank, once the filesystem has said what the thing actually is.
    static func score(_ candidate: Candidate, query: String, now: Date = Date()) -> Int? {
        guard var total = provisionalScore(path: candidate.path, query: query) else { return nil }

        // The name on disk and the name in Finder differ for the localized system
        // folders, and it is the Finder one the user typed.
        let byName = nameScore(candidate.name, query: query)
        let byPath = nameScore((candidate.path as NSString).lastPathComponent, query: query)
        total += byName - byPath

        // Folders rank above files that matched equally well. A folder is a
        // place, and someone typing a name into a launcher is more often trying
        // to get somewhere than to open one particular file inside it — which is
        // also the whole reason for surfacing folders in the first place.
        if candidate.isFolder { total += 300 }

        return total + recencyBonus(candidate.lastUsed, now: now)
    }

    // MARK: - Name

    /// How well a name answers the query.
    ///
    /// The tiers matter more than the numbers. Spotlight's `LIKE *query*` gives
    /// "Desktop" and "wolfcut_desktop_lib" and "lamp-desk.js.map" identical
    /// standing, and the difference between them — does the name *start* with
    /// what was typed, or merely contain it somewhere — is most of what makes one
    /// of the three the right answer.
    static func nameScore(_ name: String, query: String) -> Int {
        let name = name.lowercased()
        let query = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return 0 }

        let stem = (name as NSString).deletingPathExtension

        if name == query { return 1000 }
        if stem == query { return 940 }
        if name.hasPrefix(query) { return 760 }
        if stem.hasPrefix(query) { return 740 }
        // A word inside the name: "lamp-desk" answers "desk", and rather better
        // than "wolfcut_desktop_lib" does.
        if words(of: name).contains(where: { $0.hasPrefix(query) }) { return 520 }
        if name.contains(query) { return 300 }
        // Spotlight matched on a display name that differs from the name on disk,
        // which is what happens with the localized system folders.
        return 140
    }

    private static func words(of name: String) -> [String] {
        name.split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "_" || $0 == "." || $0 == "+" })
            .map(String.init)
    }

    // MARK: - Where it lives

    /// Deep is worse, from the first level down.
    ///
    /// Small steps, and bounded, so depth can break a tie between two equally
    /// good names without ever outweighing a better one. It is the tie that
    /// matters: `~/Documents` and `~/Developer/shapy/docs` both match "doc"
    /// perfectly well, and the one directly under home is the one somebody
    /// typing three letters into a launcher almost always meant.
    private static func depthPenalty(_ path: String) -> Int {
        min(max(0, relativeComponents(of: path).count - 1) * 22, 220)
    }

    /// Anything under `~/Library` is machinery. It is not excluded outright,
    /// because application data does live there and occasionally somebody wants
    /// it, but it should never win a slot from something in the user's own files.
    ///
    /// The number is large deliberately. It has to outweigh a perfect name match
    /// plus the folder bonus, or `~/Library/Application Support/Figma/
    /// DesktopProfile` beats every real folder called Desktop-something that the
    /// user has ever made — which is exactly what it did at half this value.
    private static func supportPenalty(_ path: String) -> Int {
        relativeComponents(of: path).first == "Library" ? 600 : 0
    }

    private static func recencyBonus(_ lastUsed: Date?, now: Date) -> Int {
        guard let lastUsed else { return 0 }
        let days = now.timeIntervalSince(lastUsed) / 86_400
        if days < 7 { return 140 }
        if days < 30 { return 70 }
        return 25
    }

    /// The path relative to the home directory, split into components. Paths
    /// outside home come back whole, which makes them look deep — which is the
    /// right answer, since the search is scoped to home and anything else arrived
    /// by an unusual route.
    private static func relativeComponents(of path: String) -> [String] {
        let home = NSHomeDirectory()
        let relative = path.hasPrefix(home + "/") ? String(path.dropFirst(home.count + 1)) : path
        return relative.split(separator: "/").map(String.init)
    }

    // MARK: - What is never worth showing

    /// Whether a path is build output, a dependency tree, or a cache.
    ///
    /// Shared with `FolderIndex`, which must not walk into these either. The list
    /// is names rather than patterns on purpose: a `node_modules` is a
    /// `node_modules` wherever it is, and matching on the component is both
    /// cheaper and harder to get wrong than matching on the path.
    static func isNoise(path: String) -> Bool {
        let components = path.split(separator: "/").map { $0.lowercased() }

        for component in components {
            // Dot directories are the rest of the same category — `.git`,
            // `.build`, `.venv`, `.gradle`, `.next`, `.Trash` — and catching them
            // by shape rather than by name means the list does not need to grow
            // every time a tool invents another one.
            if component.hasPrefix(".") { return true }
            if excludedDirectories.contains(component) { return true }
        }

        // Names that are only build output *in context*. `target` and `build` are
        // both perfectly ordinary things to call a folder, and excluding them
        // outright would hide real work; `target/debug` and `build/intermediates`
        // are not ambiguous at all.
        for pair in excludedSequences where contains(components, pair) { return true }

        let name = (path as NSString).lastPathComponent
        return excludedExtensions.contains((name as NSString).pathExtension.lowercased())
    }

    private static func contains(_ components: [String], _ pair: [String]) -> Bool {
        guard components.count >= pair.count else { return false }
        for start in 0 ... (components.count - pair.count) {
            if Array(components[start ..< start + pair.count]) == pair { return true }
        }
        return false
    }

    /// Whether a directory is really a document that happens to be a directory.
    /// `FolderIndex` stops at these: the inside of a Photos library is not a
    /// place anyone navigates to.
    static func isPackage(name: String) -> Bool {
        packageExtensions.contains((name as NSString).pathExtension.lowercased())
    }

    /// Lowercased, and compared against lowercased components: a folder called
    /// `Cache` and one called `cache` are the same kind of thing, and a rule that
    /// caught only one of them would look like it worked.
    private static let excludedDirectories: Set<String> = [
        "node_modules", "bower_components", "vendor",
        "deriveddata", "pods", "carthage", "coresimulator",
        "__pycache__", "site-packages", "dist-info", "egg-info",
        "cache", "caches", "containers", "group containers",
        "saved application state", "incremental", "intermediates",
        "cmakefiles", "tmp", "temp", "logs",
    ]

    private static let excludedSequences: [[String]] = [
        ["target", "debug"],
        ["target", "release"],
        ["build", "intermediates.noindex"],
        ["build", "products"],
        ["build", "generated"],
    ]

    /// Extensions that only ever name build output. Deliberately conservative:
    /// anything a person might have authored stays in the list of results, and
    /// only the things a compiler wrote are dropped.
    private static let excludedExtensions: Set<String> = [
        "o", "obj", "a", "lo", "la", "so", "class", "pyc", "pyo",
        "dia", "bc", "gcda", "gcno", "swiftmodule", "swiftdoc",
        "swiftsourceinfo", "tbd", "dsym", "d",
    ]

    private static let packageExtensions: Set<String> = [
        "app", "bundle", "framework", "xcodeproj", "xcworkspace", "playground",
        "photoslibrary", "fcpbundle", "logicx", "band", "rtfd", "download",
        "pkg", "mpkg", "sparsebundle", "docset", "lproj",
    ]
}
