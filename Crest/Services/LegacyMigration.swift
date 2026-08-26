//
//  LegacyMigration.swift
//  Crest
//

import Foundation
import OSLog

/// Carries a DiskPilot install across to Crest.
///
/// Renaming the app changed the bundle identifier, and on macOS the bundle identifier is
/// the key to almost everything a user has accumulated: `UserDefaults` lives in a domain
/// named after it, and by convention so does the Application Support directory. Ship the
/// rename without this and every setting resets, the vocabulary empties, and the meeting
/// transcripts become files nothing reads — all of it still on disk, none of it visible.
///
/// Runs once, before anything else reads a preference or touches a stored file, and
/// leaves the old copies where they are. Copying rather than moving the defaults is
/// deliberate: it costs a few kilobytes and means a user who goes back to the old build
/// still finds their settings intact.
@MainActor
enum LegacyMigration {
    /// The identity this app used to ship under.
    private static let legacyBundleIdentifier = "com.hostelhubb.DiskPilot"
    /// The Application Support folder the old build wrote to.
    private static let legacyDirectoryName = "DiskPilot"
    private static let currentDirectoryName = "Crest"

    private static let flagKey = "migratedFromDiskPilot"
    private static let logger = Logger(subsystem: "com.silvergrade.crest", category: "Migration")

    /// Call before the first read of any preference or stored file.
    static func runIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: flagKey) else { return }
        // Marked done up front. A migration that throws halfway is a bad day; one that
        // retries the same half every launch is a worse one, and both halves below are
        // written so that a partial run leaves the old data untouched and recoverable.
        defaults.set(true, forKey: flagKey)

        migrateDefaults()
        migrateApplicationSupport()
    }

    // MARK: - Preferences

    /// Copies the old domain's keys into the current one, without overwriting anything
    /// already set here.
    ///
    /// `persistentDomain(forName:)` rather than a second `UserDefaults` instance: a suite
    /// reads back the global domain folded in on top of the app's own keys, so migrating
    /// from one would drag every system-wide setting on the Mac into Crest's plist.
    private static func migrateDefaults() {
        let defaults = UserDefaults.standard
        guard let legacy = defaults.persistentDomain(forName: legacyBundleIdentifier),
              !legacy.isEmpty
        else { return }

        var copied = 0
        for (key, value) in legacy where defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
            copied += 1
        }
        logger.info("carried over \(copied, privacy: .public) setting(s) from DiskPilot")
    }

    // MARK: - Stored files

    /// Moves the old Application Support folder to the new name, merging rather than
    /// replacing if something is already there.
    private static func migrateApplicationSupport() {
        let manager = FileManager.default
        guard let base = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return }

        let legacy = base.appendingPathComponent(legacyDirectoryName, isDirectory: true)
        let current = base.appendingPathComponent(currentDirectoryName, isDirectory: true)

        guard manager.fileExists(atPath: legacy.path) else { return }

        // The old meetings index is a cache of the transcripts next to it, so it has no
        // value here and the destination rebuilds its own. Dropping it first means the
        // merge below can actually empty the legacy folder, rather than leaving it alive
        // for the sake of one file nothing will ever read.
        try? manager.removeItem(at: legacy.appendingPathComponent("Meetings/index.json"))

        if !manager.fileExists(atPath: current.path) {
            do {
                try manager.moveItem(at: legacy, to: current)
                logger.info("moved the DiskPilot data folder to Crest")
                return
            } catch {
                logger.error("couldn't move the data folder: \(error.localizedDescription, privacy: .public)")
                return
            }
        }

        // Something got there first. This should not happen now that the migration runs
        // before any store is constructed, but it is the case that loses data when it
        // does, so it stays handled rather than assumed away.
        let moved = merge(legacy, into: current)
        logger.info("merged \(moved, privacy: .public) item(s) from the DiskPilot data folder")

        if moved > 0 { invalidateDerivedIndexes(under: current) }
        removeIfEmpty(legacy)
    }

    /// Moves everything under `source` into `destination`, recursing into directories
    /// that exist on both sides.
    ///
    /// Recursion is the whole point. A shallow merge skips any name that already exists,
    /// so an empty `Meetings` folder created seconds earlier by a store's own setup would
    /// shadow the populated one being migrated, and every transcript inside it would be
    /// left behind — present on disk, invisible to the app, and not obviously missing
    /// until someone went looking for a meeting they remembered recording.
    ///
    /// Where a *file* exists on both sides the destination wins: it is the copy the
    /// running app has been writing to.
    ///
    /// - Returns: how many items were moved.
    @discardableResult
    private static func merge(_ source: URL, into destination: URL) -> Int {
        let manager = FileManager.default
        let contents = (try? manager.contentsOfDirectory(
            at: source, includingPropertiesForKeys: [.isDirectoryKey]
        )) ?? []

        var moved = 0
        for item in contents {
            let target = destination.appendingPathComponent(item.lastPathComponent)

            if !manager.fileExists(atPath: target.path) {
                do {
                    try manager.moveItem(at: item, to: target)
                    moved += 1
                } catch {
                    logger.error("couldn't move \(item.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
                continue
            }

            let isDirectory = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDirectory {
                moved += merge(item, into: target)
            }
        }

        removeIfEmpty(source)
        return moved
    }

    /// Deletes index files that are derived from the data just moved in.
    ///
    /// An index is a cache of the transcripts beside it, and a merge can leave a valid
    /// but empty one in place — which is worse than a corrupt one, because the store
    /// reads it happily and reports no meetings at all. Removing it makes the store
    /// rebuild from the transcripts themselves, which is a path it already supports.
    private static func invalidateDerivedIndexes(under directory: URL) {
        let index = directory.appendingPathComponent("Meetings/index.json")
        guard FileManager.default.fileExists(atPath: index.path) else { return }
        try? FileManager.default.removeItem(at: index)
        logger.info("dropped the meetings index so it rebuilds from the transcripts")
    }

    /// Tidies up a directory that has nothing left in it, so a migrated install does not
    /// keep an empty folder from the old name forever.
    private static func removeIfEmpty(_ directory: URL) {
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? ["not empty"]
        guard contents.isEmpty else { return }
        try? FileManager.default.removeItem(at: directory)
    }
}
