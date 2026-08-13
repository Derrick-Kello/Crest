//
//  CleanerService.swift
//  DiskPilot
//

import AppKit
import Foundation
import OSLog

/// Scans for removable junk and takes it away by moving it to the Trash.
///
/// Two rules shape everything here:
///
/// 1. **Removal is reversible.** Every item except the Trash itself is moved with
///    `FileManager.trashItem`, so a wrong guess costs the user a drag back out of
///    the Trash instead of a restore from backup. The previous implementation
///    called `removeItem` and shelled out to `npm cache clean` / `brew cleanup`,
///    which is both slower and unrecoverable.
///
/// 2. **The scan lists directories, not files.** A row is always something the
///    user can recognise — "Cache: Google Chrome" — never one of the 40,000 files
///    inside it. That keeps the review list readable and, just as importantly,
///    keeps the result set small enough that holding it in memory is free.
struct CleanerProgress: Sendable {
    var category: CleanerCategory?
    var detail: String
    var fraction: Double
}

nonisolated final class CleanerService: Sendable {
    static let shared = CleanerService()

    private let logger = Logger(subsystem: "com.diskpilot", category: "Cleaner")
    private let fileManager = FileManager.default

    // MARK: - Scan

    func scan(
        policy: CleanerPolicy,
        progress: @escaping @Sendable (CleanerProgress) -> Void = { _ in }
    ) async -> CleanerScanResult {
        let home = fileManager.homeDirectoryForCurrentUser
        let categories = CleanerCategory.allCases
        var result = CleanerScanResult(scannedAt: .now)

        for (index, category) in categories.enumerated() {
            let fraction = Double(index) / Double(categories.count)
            progress(CleanerProgress(category: category, detail: category.rawValue, fraction: fraction))

            let items = await scanCategory(category, home: home, policy: policy)
            if items.isEmpty {
                result.emptyCategories.insert(category)
            } else {
                result.items.append(contentsOf: items)
            }
        }

        result.items.sort { $0.size > $1.size }
        progress(CleanerProgress(category: nil, detail: "Done", fraction: 1))
        logger.debug("Scan finished: \(result.items.count) items, \(result.totalBytes) bytes")
        return result
    }

    private func scanCategory(
        _ category: CleanerCategory,
        home: URL,
        policy: CleanerPolicy
    ) async -> [CleanableItem] {
        switch category {
        case .caches:
            var items = await scanChildren(
                of: home.appending(path: "Library/Caches"),
                category: category,
                policy: policy,
                skip: developerCacheNames.union(["com.apple.containermanagerd"]),
                label: { "Cache: \(Self.prettyName($0))" }
            )
            items += await scanNestedAppCaches(home: home, policy: policy)
            return items

        case .logs:
            var items = await scanChildren(
                of: home.appending(path: "Library/Logs"),
                category: category,
                policy: policy,
                skip: [],
                label: { "Logs: \(Self.prettyName($0))" }
            )
            items += await scanNestedAppLogs(home: home, policy: policy)
            return items

        case .developerJunk:
            return await scanDeveloperJunk(home: home, policy: policy)

        case .appLeftovers:
            return await scanAppLeftovers(home: home, policy: policy)

        case .deviceBackups:
            return await scanChildren(
                of: home.appending(path: "Library/Application Support/MobileSync/Backup"),
                category: category,
                policy: policy,
                skip: [],
                minimumBytes: 0,
                label: { _ in "Device backup" }
            )

        case .trash:
            return await scanChildren(
                of: home.appending(path: ".Trash"),
                category: category,
                policy: policy,
                skip: [],
                minimumBytes: 0,
                includeHidden: true,
                label: { $0 }
            )
        }
    }

    /// Sizes every child of `root` one level down and returns the ones worth showing.
    /// Children under the size floor are summed into a single "smaller items" row so
    /// the total stays honest without listing hundreds of rows nobody will read.
    private func scanChildren(
        of root: URL,
        category: CleanerCategory,
        policy: CleanerPolicy,
        skip: Set<String>,
        minimumBytes: UInt64? = nil,
        includeHidden: Bool = false,
        label: @escaping @Sendable (String) -> String
    ) async -> [CleanableItem] {
        let floor = minimumBytes ?? policy.minimumItemBytes
        guard let children = childURLs(of: root, includeHidden: includeHidden) else { return [] }

        let candidates = children.filter { !skip.contains($0.lastPathComponent) }
        let sized = await mapConcurrently(candidates, maxConcurrent: 4) { url -> (URL, UInt64, Date?)? in
            let size = DiskService.shared.allocatedSize(at: url)
            guard size > 0 else { return nil }
            return (url, size, Self.lastUsedDate(of: url))
        }

        var items: [CleanableItem] = []
        var smallTotal: UInt64 = 0
        var smallCount = 0

        for case let (url, size, lastUsed)? in sized {
            guard size >= floor else {
                smallTotal += size
                smallCount += 1
                continue
            }
            items.append(CleanableItem(
                id: url.path,
                url: url,
                name: label(url.lastPathComponent),
                detail: url.lastPathComponent,
                size: size,
                category: category,
                lastUsed: lastUsed
            ))
        }

        if smallCount > 0, smallTotal > 0 {
            // Represented by its parent: selecting it removes the small children,
            // which is exactly what "and N smaller items" promises.
            items.append(CleanableItem(
                id: root.path + "#remainder",
                url: root,
                name: "\(smallCount) smaller item\(smallCount == 1 ? "" : "s")",
                detail: root.path,
                size: smallTotal,
                category: category,
                lastUsed: nil
            ))
        }
        return items
    }

    // MARK: - Nested app caches

    /// Cache directories Chromium and Electron apps keep *inside* their own
    /// Application Support folder rather than in `~/Library/Caches`.
    ///
    /// On a machine with a few Electron apps installed this is usually the single
    /// largest pile of genuinely disposable data — Kiro, Cursor, Slack and friends
    /// each hold hundreds of megabytes here — and nothing that only looks at
    /// `~/Library/Caches` will ever find it. Every name below is regenerated by the
    /// app on next launch.
    private static let nestedCacheNames = [
        "Cache", "Code Cache", "GPUCache", "CachedData", "DawnCache",
        "DawnGraphiteCache", "DawnWebGPUCache", "ShaderCache", "GrShaderCache",
        "CachedExtensionVSIXs", "component_crx_cache", "Crashpad",
        "Service Worker/CacheStorage",
    ]

    private func scanNestedAppCaches(home: URL, policy: CleanerPolicy) async -> [CleanableItem] {
        await scanNested(
            home: home,
            names: Self.nestedCacheNames,
            category: .caches,
            policy: policy,
            label: { app, folder in "\(app) — \(folder)" }
        )
    }

    private func scanNestedAppLogs(home: URL, policy: CleanerPolicy) async -> [CleanableItem] {
        await scanNested(
            home: home,
            names: ["logs", "Logs"],
            category: .logs,
            policy: policy,
            label: { app, _ in "\(app) logs" }
        )
    }

    private func scanNested(
        home: URL,
        names: [String],
        category: CleanerCategory,
        policy: CleanerPolicy,
        label: @escaping @Sendable (String, String) -> String
    ) async -> [CleanableItem] {
        let base = home.appending(path: "Library/Application Support")
        guard let apps = childURLs(of: base, includeHidden: false) else { return [] }

        // One entry per (app, cache folder) pair, sized concurrently.
        var candidates: [(app: String, name: String, url: URL)] = []
        for app in apps {
            // Apple's own Application Support entries are system state, not app caches.
            guard !app.lastPathComponent.hasPrefix("com.apple.") else { continue }
            for name in names {
                let url = app.appending(path: name)
                guard fileManager.fileExists(atPath: url.path) else { continue }
                candidates.append((app.lastPathComponent, name, url))
            }
        }

        let sized = await mapConcurrently(candidates, maxConcurrent: 4) { candidate -> CleanableItem? in
            let size = DiskService.shared.allocatedSize(at: candidate.url)
            guard size >= policy.minimumItemBytes else { return nil }
            return CleanableItem(
                id: candidate.url.path,
                url: candidate.url,
                name: label(candidate.app, candidate.name),
                detail: candidate.url.path,
                size: size,
                category: category,
                lastUsed: Self.lastUsedDate(of: candidate.url)
            )
        }
        return sized.compactMap { $0 }
    }

    // MARK: - Developer junk

    /// Names under ~/Library/Caches that belong to developer tooling. They are
    /// reported under Developer junk instead of Caches so a developer can clear
    /// build output without touching app caches, and vice versa.
    private let developerCacheNames: Set<String> = [
        "com.apple.dt.Xcode", "org.swift.swiftpm", "Yarn", "Homebrew", "pip",
        "com.microsoft.VSCode.ShipIt", "vite", "turbo", "node-gyp", "typescript",
        "deno", "go-build", "CocoaPods", "org.carthage.CarthageKit",
    ]

    private func scanDeveloperJunk(home: URL, policy: CleanerPolicy) async -> [CleanableItem] {
        struct Root: Sendable {
            let path: String
            let name: String
            /// Whether to list the children individually (DerivedData has one folder
            /// per project, which the user recognises) or report the root as one row.
            let expand: Bool
        }

        let roots: [Root] = [
            Root(path: "Library/Developer/Xcode/DerivedData", name: "Xcode DerivedData", expand: true),
            Root(path: "Library/Developer/Xcode/iOS DeviceSupport", name: "iOS DeviceSupport", expand: true),
            Root(path: "Library/Developer/Xcode/watchOS DeviceSupport", name: "watchOS DeviceSupport", expand: true),
            Root(path: "Library/Developer/Xcode/tvOS DeviceSupport", name: "tvOS DeviceSupport", expand: true),
            Root(path: "Library/Developer/Xcode/Archives", name: "Xcode Archives", expand: true),
            Root(path: "Library/Developer/CoreSimulator/Caches", name: "Simulator caches", expand: false),
            Root(path: "Library/Developer/CoreSimulator/Devices", name: "Simulator devices", expand: true),
            Root(path: ".npm/_cacache", name: "npm cache", expand: false),
            Root(path: ".gradle/caches", name: "Gradle cache", expand: false),
            Root(path: "Library/pnpm/store", name: "pnpm store", expand: false),
            Root(path: ".cargo/registry", name: "Cargo registry", expand: false),
            Root(path: "go/pkg/mod/cache", name: "Go module cache", expand: false),
        ]

        var items: [CleanableItem] = []

        // Developer caches living under ~/Library/Caches, reported here rather than
        // under Caches so the two categories stay meaningful to their audiences.
        if let cacheChildren = childURLs(of: home.appending(path: "Library/Caches"), includeHidden: false) {
            let devCaches = cacheChildren.filter { developerCacheNames.contains($0.lastPathComponent) }
            let sized = await mapConcurrently(devCaches, maxConcurrent: 4) { url -> CleanableItem? in
                let size = DiskService.shared.allocatedSize(at: url)
                guard size >= policy.minimumItemBytes else { return nil }
                return CleanableItem(
                    id: url.path,
                    url: url,
                    name: Self.prettyName(url.lastPathComponent),
                    detail: url.lastPathComponent,
                    size: size,
                    category: .developerJunk,
                    lastUsed: Self.lastUsedDate(of: url)
                )
            }
            items.append(contentsOf: sized.compactMap { $0 })
        }

        for root in roots {
            let url = home.appending(path: root.path)
            guard fileManager.fileExists(atPath: url.path) else { continue }

            if root.expand, let children = childURLs(of: url, includeHidden: false), !children.isEmpty {
                let sized = await mapConcurrently(children, maxConcurrent: 4) { child -> CleanableItem? in
                    let size = DiskService.shared.allocatedSize(at: child)
                    guard size >= policy.minimumItemBytes else { return nil }
                    return CleanableItem(
                        id: child.path,
                        url: child,
                        name: "\(root.name): \(Self.prettyName(child.lastPathComponent))",
                        detail: child.lastPathComponent,
                        size: size,
                        category: .developerJunk,
                        lastUsed: Self.lastUsedDate(of: child)
                    )
                }
                items.append(contentsOf: sized.compactMap { $0 })
            } else {
                let size = DiskService.shared.allocatedSize(at: url)
                guard size >= policy.minimumItemBytes else { continue }
                items.append(CleanableItem(
                    id: url.path,
                    url: url,
                    name: root.name,
                    detail: root.path,
                    size: size,
                    category: .developerJunk,
                    lastUsed: Self.lastUsedDate(of: url)
                ))
            }
        }
        return items
    }

    // MARK: - App leftovers

    /// Folders named after a bundle identifier whose app is no longer installed.
    ///
    /// Deliberately conservative: only reverse-DNS names are considered (so plain
    /// folders like "Google" or "Code" are never guessed at), Apple identifiers are
    /// skipped entirely because most of them belong to system services that have no
    /// app bundle, and anything sharing a prefix with an installed app is kept —
    /// that is how helper identifiers like `com.google.Chrome.helper` survive.
    private func scanAppLeftovers(home: URL, policy: CleanerPolicy) async -> [CleanableItem] {
        let roots = [
            "Library/Application Support",
            "Library/Caches",
            "Library/Preferences",
            "Library/Logs",
            "Library/Saved Application State",
            "Library/Containers",
            "Library/HTTPStorages",
            "Library/WebKit",
        ]

        let installed = installedBundleIdentifiers()
        var candidates: [URL] = []

        for root in roots {
            guard let children = childURLs(of: home.appending(path: root), includeHidden: false) else { continue }
            for child in children {
                let bundleID = Self.bundleIdentifier(fromFolderName: child.lastPathComponent)
                guard let bundleID else { continue }
                guard !bundleID.hasPrefix("com.apple.") else { continue }
                guard !isInstalled(bundleID, installed: installed) else { continue }
                candidates.append(child)
            }
        }

        let sized = await mapConcurrently(candidates, maxConcurrent: 4) { url -> CleanableItem? in
            let size = DiskService.shared.allocatedSize(at: url)
            guard size >= policy.minimumItemBytes else { return nil }
            let bundleID = Self.bundleIdentifier(fromFolderName: url.lastPathComponent) ?? url.lastPathComponent
            return CleanableItem(
                id: url.path,
                url: url,
                name: Self.appName(fromBundleIdentifier: bundleID),
                detail: bundleID,
                size: size,
                category: .appLeftovers,
                lastUsed: Self.lastUsedDate(of: url)
            )
        }
        return sized.compactMap { $0 }
    }

    /// Bundle IDs of every app LaunchServices knows about, used only for the
    /// prefix test. Exact matches go through `NSWorkspace` directly.
    private func installedBundleIdentifiers() -> Set<String> {
        var ids: Set<String> = []
        let appRoots = [
            "/Applications",
            "/System/Applications",
            fileManager.homeDirectoryForCurrentUser.appending(path: "Applications").path,
        ]
        for root in appRoots {
            guard let enumerator = fileManager.enumerator(
                at: URL(fileURLWithPath: root),
                includingPropertiesForKeys: [.isApplicationKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for case let url as URL in enumerator where url.pathExtension == "app" {
                if let bundle = Bundle(url: url), let id = bundle.bundleIdentifier {
                    ids.insert(id)
                }
                enumerator.skipDescendants()
            }
        }
        return ids
    }

    private func isInstalled(_ bundleID: String, installed: Set<String>) -> Bool {
        if installed.contains(bundleID) { return true }
        if NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil { return true }
        // Helper / component identifiers hang off an installed app's identifier.
        return installed.contains { bundleID.hasPrefix($0 + ".") || $0.hasPrefix(bundleID + ".") }
    }

    // MARK: - Removal

    /// Moves the given items to the Trash. Items in the Trash category are deleted
    /// outright — there is nowhere further for them to go — which is why the UI
    /// labels that one differently.
    func remove(_ items: [CleanableItem]) async -> CleanerRemovalReport {
        var report = CleanerRemovalReport()

        for item in items {
            // A remainder row stands for the small children of a folder, so the
            // folder itself is never the deletion target and gets validated
            // per-child inside `trashSmallChildren` instead.
            let isRemainder = item.id.hasSuffix("#remainder")

            // Checked independent of how the item got into the list. A bug in a
            // scanner is a bug; a bug that trashes ~/Documents is unrecoverable.
            guard isRemainder || Self.isRemovable(item.url) else {
                logger.fault("Refused removal outside allowed roots: \(item.url.path, privacy: .public)")
                report.failures.append((name: item.name, reason: "Outside the folders DiskPilot is allowed to clean"))
                continue
            }

            do {
                if isRemainder {
                    try trashSmallChildren(under: item.url)
                } else if item.category.removalIsPermanent {
                    try fileManager.removeItem(at: item.url)
                } else {
                    try fileManager.trashItem(at: item.url, resultingItemURL: nil)
                }
                report.bytesReclaimed += item.size
                report.itemsRemoved += 1
            } catch {
                logger.error("Remove failed for \(item.url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                report.failures.append((name: item.name, reason: error.localizedDescription))
            }
        }

        DiskService.shared.invalidateSizeCache()
        return report
    }

    /// The "N smaller items" row stands in for the small children of a folder, so
    /// removing it must trash exactly those children and leave the folder itself —
    /// trashing `~/Library/Caches` wholesale would be a very different action.
    private func trashSmallChildren(under root: URL, largerThan floor: UInt64? = nil) throws {
        guard let children = childURLs(of: root, includeHidden: false) else { return }
        let limit = floor ?? CleanerPolicy.default.minimumItemBytes
        for child in children {
            guard Self.isRemovable(child) else { continue }
            let size = DiskService.shared.allocatedSize(at: child)
            guard size > 0, size < limit else { continue }
            try? fileManager.trashItem(at: child, resultingItemURL: nil)
        }
    }

    // MARK: - Safety

    /// An allowlist, checked at the moment of removal.
    ///
    /// A path is removable only if it sits *strictly inside* one of these roots —
    /// the roots themselves are rejected, so no bug can trash `~/Library/Caches`
    /// whole. Symlinks are resolved first so a link planted inside an allowed root
    /// cannot point the removal at `~/Documents`.
    static func isRemovable(_ url: URL) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath()
        let allowedRoots = [
            "Library/Caches", "Library/Logs", "Library/Application Support",
            "Library/Preferences", "Library/Saved Application State",
            "Library/Containers", "Library/HTTPStorages", "Library/WebKit",
            "Library/Developer", "Library/pnpm", ".Trash", ".npm", ".gradle",
            ".cargo", "go/pkg",
        ].map { home.appending(path: $0).standardizedFileURL.path }

        let target = url.resolvingSymlinksInPath().standardizedFileURL.path
        guard target.hasPrefix(home.path + "/") else { return false }

        return allowedRoots.contains { root in
            target != root && target.hasPrefix(root + "/")
        }
    }

    // MARK: - Helpers

    private func childURLs(of root: URL, includeHidden: Bool) -> [URL]? {
        var options: FileManager.DirectoryEnumerationOptions = []
        if !includeHidden { options.insert(.skipsHiddenFiles) }
        return try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: options
        )
    }

    private static func lastUsedDate(of url: URL) -> Date? {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .contentAccessDateKey])
        let modified = values?.contentModificationDate
        let accessed = values?.contentAccessDate
        switch (modified, accessed) {
        case let (m?, a?): return max(m, a)
        case let (m?, nil): return m
        case let (nil, a?): return a
        default: return nil
        }
    }

    /// `com.company.App.plist` / `com.company.App.savedState` → `com.company.App`,
    /// and anything that isn't reverse-DNS shaped → nil.
    private static func bundleIdentifier(fromFolderName name: String) -> String? {
        var trimmed = name
        for suffix in [".plist", ".savedState", ".binarycookies"] where trimmed.hasSuffix(suffix) {
            trimmed = String(trimmed.dropLast(suffix.count))
        }
        let parts = trimmed.split(separator: ".")
        guard parts.count >= 3 else { return nil }
        guard trimmed.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil else { return nil }
        return trimmed
    }

    /// Best-effort human name for a bundle ID we can no longer look up, since the
    /// app is gone: `com.figma.Desktop` → `Figma Desktop`.
    private static func appName(fromBundleIdentifier id: String) -> String {
        let parts = id.split(separator: ".").dropFirst(1)
        let words = parts.map { part -> String in
            part.prefix(1).uppercased() + part.dropFirst()
        }
        let name = words.joined(separator: " ")
        return name.isEmpty ? id : name
    }

    /// Resolves a bundle-ID folder name to the app's real name when that app is
    /// installed. When it isn't, the raw folder name is shown rather than a guess —
    /// `com.apple.helpd` is more honest, and more searchable, than "Apple Helpd".
    /// The guess is reserved for App leftovers, where the app is gone by definition.
    private static func prettyName(_ folderName: String) -> String {
        guard let id = bundleIdentifier(fromFolderName: folderName),
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
        else { return folderName }
        return url.deletingPathExtension().lastPathComponent
    }
}
