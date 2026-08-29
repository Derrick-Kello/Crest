//
//  UninstallerService.swift
//  Crest
//

import AppKit
import Foundation
import OSLog
import SwiftUI

/// Where a leftover was found, in the terms a person would use.
nonisolated enum LeftoverCategory: String, CaseIterable, Identifiable, Sendable {
    case application = "Application"
    case support = "Support files"
    case preferences = "Preferences"
    case containers = "Containers"
    case caches = "Caches"
    case logs = "Logs"
    case savedState = "Saved state"
    case startup = "Startup items"
    case other = "Other"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .application: "app.fill"
        case .support: "folder"
        case .preferences: "slider.horizontal.3"
        case .containers: "cube.box"
        case .caches: "shippingbox"
        case .logs: "doc.text"
        case .savedState: "macwindow"
        case .startup: "power"
        case .other: "questionmark.folder"
        }
    }

    var accent: Color {
        switch self {
        case .application: .blue
        case .support: .purple
        case .preferences: .teal
        case .containers: .indigo
        case .caches: .orange
        case .logs: .mint
        case .savedState: .gray
        case .startup: .red
        case .other: .secondary
        }
    }

    /// The app bundle itself is always removed; everything else is a choice the
    /// user makes, and the defaults follow how recoverable each kind of file is.
    var selectedByDefault: Bool { self != .other }
}

/// One file or folder the uninstaller found.
nonisolated struct LeftoverItem: Identifiable, Hashable, Sendable {
    let url: URL
    let category: LeftoverCategory
    let size: UInt64
    /// True when this lives under `/Library` and moving it needs an administrator.
    let needsAdmin: Bool

    var id: String { url.path }
    var name: String { url.lastPathComponent }
    var location: String {
        url.deletingLastPathComponent().path
            .replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
    var formattedSize: String { ByteFormat.string(size) }
}

/// The app being removed.
nonisolated struct UninstallTarget: Identifiable, Hashable, Sendable {
    let url: URL
    let name: String
    let bundleIdentifier: String?
    let version: String?

    var id: String { url.path }
}

nonisolated struct UninstallScan: Sendable {
    let target: UninstallTarget
    var items: [LeftoverItem]

    var totalBytes: UInt64 { items.reduce(0) { $0 + $1.size } }

    func items(in category: LeftoverCategory) -> [LeftoverItem] {
        items.filter { $0.category == category }
    }

    var presentCategories: [LeftoverCategory] {
        LeftoverCategory.allCases.filter { category in items.contains { $0.category == category } }
    }
}

nonisolated struct UninstallReport: Sendable {
    var removed: Int = 0
    var bytesFreed: UInt64 = 0
    var failures: [String] = []

    var summary: String {
        if removed == 0 { return "Nothing was removed." }
        let freed = ByteFormat.string(bytesFreed)
        let base = "Moved \(removed) item\(removed == 1 ? "" : "s") to the Trash — \(freed)"
        return failures.isEmpty ? base : "\(base). \(failures.count) item\(failures.count == 1 ? "" : "s") could not be moved."
    }
}

/// Finds what an app leaves behind, and moves the lot to the Trash.
///
/// The scan is deliberately narrow. It only looks inside a fixed set of known
/// support directories, and inside those it only accepts a name that *is* the
/// bundle identifier, a child namespace of it, or the app's own name. A looser
/// rule — substring matching, or walking company folders — finds a few more
/// megabytes and eventually proposes deleting something that belongs to a
/// different app. Nothing is ever deleted outright: every item goes to the Trash,
/// so a wrong guess costs the user a drag back out.
nonisolated final class UninstallerService: Sendable {
    static let shared = UninstallerService()

    private let logger = Logger(subsystem: "com.smarthive.crest", category: "Uninstaller")

    private init() {}

    // MARK: - Target

    func target(for url: URL) -> UninstallTarget? {
        guard url.pathExtension == "app" else { return nil }
        let bundle = Bundle(url: url)
        return UninstallTarget(
            url: url,
            name: url.deletingPathExtension().lastPathComponent,
            bundleIdentifier: bundle?.bundleIdentifier,
            version: bundle?.infoDictionary?["CFBundleShortVersionString"] as? String
        )
    }

    // MARK: - Scan

    /// Search roots, paired with the category anything found there belongs to.
    private struct Root {
        let path: String
        let category: LeftoverCategory
        /// Accepts the identifier anywhere in the name rather than only at the
        /// start. Group containers are the one place that needs it: they carry a
        /// team prefix (`22MMUN2RN5.com.foo.bar`) that no strict rule can predict.
        /// Everywhere else, `contains` matches a neighbouring app whose identifier
        /// merely starts the same way, so those roots stay strict.
        let looseMatch: Bool
        let systemOwned: Bool

        init(_ path: String, _ category: LeftoverCategory, loose: Bool = false, system: Bool = false) {
            self.path = path
            self.category = category
            self.looseMatch = loose
            self.systemOwned = system
        }
    }

    private static func roots(home: String) -> [Root] {
        [
            Root("\(home)/Library/Application Support", .support),
            Root("\(home)/Library/Containers", .containers),
            Root("\(home)/Library/Group Containers", .containers, loose: true),
            Root("\(home)/Library/Application Scripts", .containers),
            Root("\(home)/Library/Preferences", .preferences),
            Root("\(home)/Library/Preferences/ByHost", .preferences),
            Root("\(home)/Library/Caches", .caches),
            Root("\(home)/Library/HTTPStorages", .caches),
            Root("\(home)/Library/WebKit", .caches),
            Root("\(home)/Library/Cookies", .caches),
            Root("\(home)/Library/Logs", .logs),
            Root("\(home)/Library/Saved Application State", .savedState),
            Root("\(home)/Library/LaunchAgents", .startup),
            Root("/Library/Application Support", .support, system: true),
            Root("/Library/Caches", .caches, system: true),
            Root("/Library/Preferences", .preferences, system: true),
            Root("/Library/Logs", .logs, system: true),
            Root("/Library/LaunchAgents", .startup, system: true),
            Root("/Library/LaunchDaemons", .startup, system: true),
            Root("/Library/PrivilegedHelperTools", .startup, system: true),
        ]
    }

    func scan(_ target: UninstallTarget) async -> UninstallScan {
        await Task.detached(priority: .userInitiated) {
            var items: [LeftoverItem] = []

            let appSize = DiskService.shared.allocatedSize(at: target.url)
            items.append(LeftoverItem(
                url: target.url,
                category: .application,
                size: appSize,
                needsAdmin: !FileManager.default.isWritableFile(atPath: target.url.deletingLastPathComponent().path)
            ))

            let home = NSHomeDirectory()
            let bundleID = target.bundleIdentifier
            let appName = target.name

            for root in Self.roots(home: home) {
                guard let entries = try? FileManager.default.contentsOfDirectory(
                    at: URL(fileURLWithPath: root.path),
                    includingPropertiesForKeys: nil,
                    options: [.skipsSubdirectoryDescendants]
                ) else { continue }

                for url in entries {
                    guard Self.matches(url.lastPathComponent, bundleID: bundleID, appName: appName, loose: root.looseMatch) else { continue }
                    let size = DiskService.shared.allocatedSize(at: url)
                    items.append(LeftoverItem(
                        url: url,
                        category: root.category,
                        size: size,
                        needsAdmin: root.systemOwned
                    ))
                }
            }

            // Vendor folders — "BraveSoftware", "Google", "Adobe" — hold an app's
            // real data but carry the company's name, not the app's, so the strict
            // rules above never see them. They are found separately and filed under
            // Other, which starts unticked: the folder may be shared with another
            // app from the same vendor, and that is the user's call, not ours.
            if let token = Self.vendorToken(for: bundleID) {
                for root in Self.vendorRoots(home: home) {
                    guard let entries = try? FileManager.default.contentsOfDirectory(
                        at: URL(fileURLWithPath: root.path),
                        includingPropertiesForKeys: nil,
                        options: [.skipsSubdirectoryDescendants]
                    ) else { continue }

                    for url in entries where url.lastPathComponent.lowercased().hasPrefix(token) {
                        items.append(LeftoverItem(
                            url: url,
                            category: .other,
                            size: DiskService.shared.allocatedSize(at: url),
                            needsAdmin: root.systemOwned
                        ))
                    }
                }
            }

            // The same path can sit under two roots (ByHost is inside Preferences),
            // and a duplicate row would be counted twice in the total. Strict matches
            // were appended first, so keeping the first occurrence keeps the more
            // specific category.
            var seen = Set<String>()
            let unique = items.filter { seen.insert($0.url.path).inserted }

            return UninstallScan(
                target: target,
                items: unique.sorted { $0.size > $1.size }
            )
        }.value
    }

    /// Only the two roots where a vendor folder is worth looking for. Preferences
    /// and containers are always named by bundle identifier, so a company-name pass
    /// over those would only ever produce false positives.
    private static func vendorRoots(home: String) -> [Root] {
        [
            Root("\(home)/Library/Application Support", .other),
            Root("\(home)/Library/Caches", .other),
            Root("/Library/Application Support", .other, system: true),
        ]
    }

    /// The company component of a reverse-domain identifier — `com.brave.Browser`
    /// gives "brave", which finds "BraveSoftware".
    ///
    /// Short and generic tokens are refused outright. A two-letter token would
    /// prefix-match a third of `Application Support`, and "apple" would propose
    /// deleting parts of macOS.
    static func vendorToken(for bundleID: String?) -> String? {
        guard let bundleID else { return nil }
        let parts = bundleID.split(separator: ".")
        guard parts.count >= 3 else { return nil }
        let token = parts[1].lowercased()
        let reserved: Set<String> = ["apple", "com", "org", "net", "www", "mac", "macos", "software", "systems", "group"]
        guard token.count >= 4, !reserved.contains(token) else { return nil }
        return token
    }

    /// The whole safety story of this feature is in this function.
    ///
    /// `strict` accepts the bundle identifier, a child of it (`com.foo.app.helper`)
    /// and the app's own name. `loose` additionally accepts the identifier appearing
    /// inside a longer name, which is what group containers and launch agents look
    /// like — but only ever the identifier, never the app name, because a name like
    /// "Mail" or "Notes" would match half the Library.
    static func matches(_ filename: String, bundleID: String?, appName: String, loose: Bool) -> Bool {
        let stem = Self.stripKnownExtension(filename)

        if let bundleID, !bundleID.isEmpty {
            if stem == bundleID || stem.hasPrefix(bundleID + ".") { return true }
            if loose, stem.contains(bundleID) { return true }
        }

        // Names are compared case-insensitively but must match in full: a folder
        // called "Spotify" belongs to Spotify, one called "Spotify Helper Data"
        // might belong to anything.
        return stem.compare(appName, options: .caseInsensitive) == .orderedSame
    }

    private static func stripKnownExtension(_ filename: String) -> String {
        for suffix in [".plist", ".savedState", ".binarycookies"] where filename.hasSuffix(suffix) {
            return String(filename.dropLast(suffix.count))
        }
        return filename
    }

    // MARK: - Removal

    /// An app still running holds its own files open and, worse, rewrites its
    /// preferences on quit — putting back what was just removed. So it is asked to
    /// quit first, and only forced if it refuses.
    @MainActor
    func quitIfRunning(_ target: UninstallTarget) async {
        let running = NSWorkspace.shared.runningApplications.filter { app in
            app.bundleURL?.standardizedFileURL == target.url.standardizedFileURL
                || (target.bundleIdentifier != nil && app.bundleIdentifier == target.bundleIdentifier)
        }
        guard !running.isEmpty else { return }

        for app in running { app.terminate() }
        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(150))
            if running.allSatisfy(\.isTerminated) { return }
        }
        for app in running where !app.isTerminated { app.forceTerminate() }
        try? await Task.sleep(for: .milliseconds(300))
    }

    func remove(_ items: [LeftoverItem]) async -> UninstallReport {
        await Task.detached(priority: .userInitiated) { [self] in
            var report = UninstallReport()
            for item in items {
                do {
                    try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
                    report.removed += 1
                    report.bytesFreed += item.size
                } catch {
                    logger.error("Could not trash \(item.url.path, privacy: .public)")
                    report.failures.append(item.needsAdmin
                        ? "\(item.name) needs an administrator to remove."
                        : "\(item.name): \(error.localizedDescription)")
                }
            }
            DiskService.shared.invalidateSizeCache()
            return report
        }.value
    }
}
