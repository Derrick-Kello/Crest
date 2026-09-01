//
//  FileSearchService.swift
//  Crest
//

import AppKit
import Foundation

/// Finds files and folders by name through Spotlight's local index.
///
/// Spotlight decides *what* matches; `FileRanking` decides what is worth
/// showing and in what order, which is a judgement Spotlight's own sort is in
/// no position to make.
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
        /// `d ` — folders and nothing else.
        case folders

        var limit: Int { self == .mixed ? 6 : 24 }
        /// Below this a query matches most of the disk. A scoped search is an
        /// explicit request, so it starts sooner.
        var minimumQueryLength: Int { self == .mixed ? 3 : 2 }
        var foldersOnly: Bool { self == .folders }
    }

    /// How many of Spotlight's answers to look at before choosing.
    ///
    /// The bug this exists for: the service used to take the first six results
    /// Spotlight handed back and stop. Spotlight sorts by last-used date, almost
    /// nothing on a developer's Mac has one, so those six were effectively
    /// arbitrary — measured on a real home directory, a search for "desk"
    /// returned 790 rows of which 36 were folders, and exactly one folder made
    /// the cut. Every other folder was past the cut, which is what "we don't
    /// index folders" actually looked like from the outside.
    ///
    /// A thousand paths cost about two milliseconds to read, so the net is wide.
    private static let scanLimit = 1000

    /// How many survivors are worth a trip to the filesystem.
    ///
    /// Reading what something *is* costs roughly a tenth of a millisecond per
    /// path through `URLResourceValues`, against about a millisecond through the
    /// metadata store — but neither is free enough to spend on a thousand. The
    /// path-only score picks the shortlist and only these get looked up, which
    /// keeps the whole pass in single-digit milliseconds however broad the query.
    private static let inspectLimit = 60

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
        let name = NSPredicate(format: "kMDItemDisplayName LIKE[cd] %@", "*\(escape(text))*")
        // Asking Spotlight for folders is far better than asking for everything
        // and throwing files away: the scan window is finite, and a folders-only
        // search that filtered client-side would spend the whole window on files
        // and come back with two rows.
        query.predicate = mode.foldersOnly
            ? NSCompoundPredicate(andPredicateWithSubpredicates: [
                name,
                NSPredicate(format: "kMDItemContentTypeTree == %@", "public.folder"),
            ])
            : name
        // The user's own files only. Searching the whole machine looked more
        // thorough and was worse: "wifi" came back with CoEx-Table plists out of
        // a private framework, which is never what someone typing into a launcher
        // is after, and those rows pushed the real answers off the list.
        query.searchScopes = [NSMetadataQueryUserHomeScope]
        // Recency decides which results are *looked at* when there are more than
        // the scan window holds. It no longer decides the order they are shown in
        // — `FileRanking` does that — because on a machine where almost nothing
        // carries a last-used date, sorting by it is barely sorting at all.
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

    /// Two passes, because the two halves of the answer cost three orders of
    /// magnitude apart. The first reads nothing but paths and throws away the
    /// build output, the caches and the dependency trees; the second asks the
    /// filesystem what the shortlist actually is.
    private func collect() {
        guard let query else { return }
        query.disableUpdates()
        defer { query.enableUpdates() }

        let shortlist = shortlisted(query)
        let items = inspect(shortlist)

        guard items.map(\.id) != results.map(\.id) else { return }
        results = items
        generation += 1
    }

    /// The cheap pass: paths, filtered and ranked on their own.
    private func shortlisted(_ query: NSMetadataQuery) -> [String] {
        var candidates: [(path: String, score: Int)] = []
        var seen: Set<String> = []

        for index in 0 ..< min(query.resultCount, Self.scanLimit) {
            guard let result = query.result(at: index) as? NSMetadataItem,
                  let path = result.value(forAttribute: NSMetadataItemPathKey) as? String
            else { continue }

            // Applications already have their own section, and bundle internals
            // are never a useful answer to a launcher query.
            guard !path.contains(".app/"), !path.hasSuffix(".app") else { continue }
            guard seen.insert(path).inserted else { continue }
            guard let score = FileRanking.provisionalScore(path: path, query: currentQueryText) else { continue }

            candidates.append((path, score))
        }

        return candidates
            .sorted { $0.score == $1.score ? $0.path < $1.path : $0.score > $1.score }
            .prefix(Self.inspectLimit)
            .map(\.path)
    }

    /// The pass that costs something: one batched resource lookup per path.
    ///
    /// `URLResourceValues` rather than more `NSMetadataItem` attributes — it
    /// answers all four questions in one stat, is around twenty times faster, and
    /// is the more accurate of the two about whether something is a directory,
    /// which is the answer everything else here hangs on.
    private func inspect(_ paths: [String]) -> [CatalogItem] {
        let now = Date()
        var scored: [(item: CatalogItem, score: Int)] = []

        for path in paths {
            let url = URL(fileURLWithPath: path)
            let values = try? url.resourceValues(forKeys: [
                .isDirectoryKey, .localizedNameKey, .contentAccessDateKey, .fileSizeKey,
            ])

            // A package is a directory the filesystem happens to store as one —
            // `Crest.xcodeproj`, a Photos library, a `.musiclibrary`. Calling it a
            // folder in the subtitle would be a lie, and giving it the folder
            // bonus would rank a document above the folder it lives in.
            let isFolder = (values?.isDirectory ?? false) && !FileRanking.isPackage(name: url.lastPathComponent)
            if mode.foldersOnly, !isFolder { continue }

            let name = values?.localizedName ?? url.lastPathComponent
            let candidate = FileRanking.Candidate(
                path: path,
                name: name,
                isFolder: isFolder,
                lastUsed: values?.contentAccessDate
            )
            guard let rank = FileRanking.score(candidate, query: currentQueryText, now: now) else { continue }

            scored.append((
                CatalogItem(
                    id: "file:" + path,
                    title: name,
                    subtitle: subtitle(for: url, isFolder: isFolder, size: values?.fileSize),
                    category: .file,
                    iconPath: path,
                    symbolName: isFolder ? "folder" : nil,
                    keys: CatalogItem.keys(title: name, weak: [path]),
                    action: .openFile(path: path)
                ),
                rank
            ))
        }

        return scored
            .sorted { $0.score == $1.score ? $0.item.title < $1.item.title : $0.score > $1.score }
            .prefix(mode.limit)
            .map(\.item)
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
    ///
    /// A folder gets no size. The figure Spotlight holds for a directory is the
    /// size of the directory entry rather than of what is inside it, so printing
    /// it would tell the user that their Downloads folder is 320 bytes.
    private func subtitle(for url: URL, isFolder: Bool, size: Int?) -> String {
        let location = abbreviate(url.deletingLastPathComponent().path)
        guard !isFolder else { return "Folder — \(location)" }
        guard let size, size > 0 else { return location }
        return "\(location) — \(ByteFormat.string(UInt64(size)))"
    }

    private func abbreviate(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
