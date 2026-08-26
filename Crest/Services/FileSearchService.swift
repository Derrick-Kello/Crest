//
//  FileSearchService.swift
//  Crest
//

import AppKit
import Foundation

/// Finds files and folders by name through Spotlight's local index.
///
/// `NSMetadataQuery` reads the index macOS already maintains on this machine —
/// nothing leaves the Mac, and there is no second index for Crest to build,
/// store, or keep in sync. Results arrive asynchronously, so the command bar
/// shows apps and tools immediately and folds files in when they land.
@MainActor
@Observable
final class FileSearchService {
    static let shared = FileSearchService()

    /// The most recent results, already scored and ready to merge.
    private(set) var results: [CatalogItem] = []
    /// Bumped whenever `results` changes, so a view can re-run its query.
    private(set) var generation = 0

    /// How much of the list files are allowed to take.
    ///
    /// Mixed in with everything else they are a garnish — six rows at most, or the
    /// app someone is actually launching gets pushed off the bottom by a folder
    /// that happens to share three letters with it. When the query says files and
    /// nothing else, the whole list is theirs.
    enum Mode: Equatable {
        case mixed
        case dedicated

        var limit: Int { self == .mixed ? 6 : 24 }
        /// Below this a query matches most of the disk. A dedicated search is an
        /// explicit request, so it starts sooner.
        var minimumQueryLength: Int { self == .mixed ? 3 : 2 }
    }

    private var query: NSMetadataQuery?
    private var observers: [NSObjectProtocol] = []
    private var currentQueryText = ""
    private var mode: Mode = .mixed
    private var pendingTask: Task<Void, Never>?

    private init() {}

    /// Starts a search, replacing whatever was running.
    ///
    /// Debounced: Spotlight queries are cheap but not free, and starting one per
    /// keystroke means the answer to a half-typed word arrives after the answer to
    /// the whole one, which makes the list flicker backwards.
    func search(_ text: String, mode: Mode = .mixed) {
        guard Preferences.fileSearchEnabled else {
            cancel()
            return
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= mode.minimumQueryLength else {
            cancel()
            return
        }
        guard trimmed != currentQueryText || mode != self.mode else { return }
        currentQueryText = trimmed
        self.mode = mode

        pendingTask?.cancel()
        pendingTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(140))
            guard !Task.isCancelled, let self else { return }
            self.start(trimmed)
        }
    }

    func cancel() {
        pendingTask?.cancel()
        pendingTask = nil
        currentQueryText = ""
        stopQuery()
        if !results.isEmpty {
            results = []
            generation += 1
        }
    }

    // MARK: - Query

    private func start(_ text: String) {
        stopQuery()

        let query = NSMetadataQuery()
        // Name-only. A content search would return a hundred documents that merely
        // mention the word, which is not what someone typing into a launcher wants.
        query.predicate = NSPredicate(
            format: "kMDItemDisplayName LIKE[cd] %@", "*\(escape(text))*"
        )
        // The user's own files only. Searching the whole machine looked more
        // thorough and was worse: "wifi" came back with CoEx-Table plists out of
        // a private framework, which is never what someone typing into a launcher
        // is after, and those rows pushed the real answers off the list.
        query.searchScopes = [NSMetadataQueryUserHomeScope]
        // Most recently opened first: recency is the best available stand-in for
        // relevance when every result matched the name equally well.
        query.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemLastUsedDateKey, ascending: false)]
        query.notificationBatchingInterval = 0.2

        // `@Sendable` because `NotificationCenter` may call it from anywhere; the
        // queue is `.main`, so the isolation assumption inside holds.
        let finish: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.collect() }
        }
        observers = [
            NotificationCenter.default.addObserver(
                forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main, using: finish
            ),
            NotificationCenter.default.addObserver(
                forName: .NSMetadataQueryDidUpdate, object: query, queue: .main, using: finish
            ),
        ]

        self.query = query
        query.start()
    }

    private func collect() {
        guard let query else { return }
        query.disableUpdates()
        defer { query.enableUpdates() }

        var items: [CatalogItem] = []
        var seen: Set<String> = []

        for index in 0..<query.resultCount {
            guard items.count < mode.limit,
                  let result = query.result(at: index) as? NSMetadataItem,
                  let path = result.value(forAttribute: NSMetadataItemPathKey) as? String
            else { continue }

            // Applications already have their own section, and bundle internals
            // are never a useful answer to a launcher query.
            guard !path.contains(".app/"), !path.hasSuffix(".app") else { continue }
            guard seen.insert(path).inserted else { continue }

            let url = URL(fileURLWithPath: path)
            let name = (result.value(forAttribute: NSMetadataItemDisplayNameKey) as? String)
                ?? url.lastPathComponent

            items.append(CatalogItem(
                id: "file:" + path,
                title: name,
                subtitle: subtitle(for: result, url: url),
                category: .file,
                iconPath: path,
                keys: CatalogItem.keys(title: name, weak: [path]),
                action: .openFile(path: path)
            ))
        }

        guard items.map(\.id) != results.map(\.id) else { return }
        results = items
        generation += 1
    }

    private func stopQuery() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        query?.stop()
        query = nil
    }

    /// `LIKE` treats these as wildcards, so a query containing one would otherwise
    /// mean something the user did not type.
    private func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "*", with: "\\*")
            .replacingOccurrences(of: "?", with: "\\?")
    }

    /// Location first, then size — the location is what tells two files with the
    /// same name apart, which is the question a file result usually has to answer.
    private func subtitle(for result: NSMetadataItem, url: URL) -> String {
        let location = abbreviate(url.deletingLastPathComponent().path)
        guard let size = result.value(forAttribute: NSMetadataItemFSSizeKey) as? NSNumber,
              size.uint64Value > 0
        else { return location }
        return "\(location) — \(ByteFormat.string(size.uint64Value))"
    }

    private func abbreviate(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
