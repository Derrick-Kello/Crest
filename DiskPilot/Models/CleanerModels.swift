//
//  CleanerModels.swift
//  DiskPilot
//

import Foundation
import SwiftUI

/// The groups the cleaner reports. Every group answers the same three questions
/// for the user: what is this, is it safe, and what happens if I remove it.
enum CleanerCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case appLeftovers = "App leftovers"
    case caches = "Caches"
    case developerJunk = "Developer junk"
    case logs = "Logs"
    case deviceBackups = "Device backups"
    case trash = "Trash"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .appLeftovers: "app.dashed"
        case .caches: "shippingbox"
        case .developerJunk: "hammer"
        case .logs: "doc.text"
        case .deviceBackups: "iphone"
        case .trash: "trash"
        }
    }

    /// One line under the category header. Says the consequence, not the mechanism —
    /// the user is deciding whether to trust the checkbox, not reading documentation.
    var blurb: String {
        switch self {
        case .appLeftovers:
            "Support files, preferences and caches from apps that are no longer installed."
        case .caches:
            "Rebuilt automatically. Apps may open slower once, and downloaded content re-downloads."
        case .developerJunk:
            "Build output and package caches. Your tools regenerate these on the next build."
        case .logs:
            "Diagnostic text written by apps. Nothing reads them once the app has moved on."
        case .deviceBackups:
            "Old iPhone and iPad backups. A new backup is made next time you connect the device."
        case .trash:
            "Items already in the Trash. Emptying is permanent."
        }
    }

    /// Categories preselected on a fresh scan. Backups and Trash are opt-in because
    /// one is irreplaceable and the other is the user's own undo buffer.
    var selectedByDefault: Bool {
        switch self {
        case .appLeftovers, .caches, .developerJunk, .logs: true
        case .deviceBackups, .trash: false
        }
    }

    /// Trash is the one category we cannot move *to* the Trash — removing it is
    /// a permanent delete and the UI has to say so out loud.
    var removalIsPermanent: Bool { self == .trash }

    var accent: Color {
        switch self {
        case .appLeftovers: .purple
        case .caches: .blue
        case .developerJunk: .orange
        case .logs: .teal
        case .deviceBackups: .pink
        case .trash: .gray
        }
    }
}

/// A single reviewable row. One item is always a directory or file the user can
/// reason about ("Cache: Google Chrome"), never an individual leaf file — the
/// review list stays readable and the scan stays cheap.
struct CleanableItem: Identifiable, Hashable, Sendable {
    let id: String
    let url: URL
    let name: String
    let detail: String
    let size: UInt64
    let category: CleanerCategory
    let lastUsed: Date?

    var formattedSize: String { ByteFormat.string(size) }

    var ageDescription: String? {
        guard let lastUsed else { return nil }
        let days = Calendar.current.dateComponents([.day], from: lastUsed, to: Date()).day ?? 0
        if days <= 0 { return "used today" }
        if days == 1 { return "used yesterday" }
        if days < 30 { return "used \(days) days ago" }
        let months = days / 30
        if months < 12 { return "used \(months) month\(months == 1 ? "" : "s") ago" }
        let years = months / 12
        return "used \(years) year\(years == 1 ? "" : "s") ago"
    }
}

struct CleanerScanResult: Sendable {
    var items: [CleanableItem] = []
    var scannedAt: Date = .now
    /// Categories that produced nothing, so the UI can say "clean" instead of
    /// silently omitting the row and looking like the scan skipped it.
    var emptyCategories: Set<CleanerCategory> = []

    var totalBytes: UInt64 { items.reduce(0) { $0 + $1.size } }
    var isEmpty: Bool { items.isEmpty }

    func items(in category: CleanerCategory) -> [CleanableItem] {
        items.filter { $0.category == category }
    }

    func bytes(in category: CleanerCategory) -> UInt64 {
        items(in: category).reduce(0) { $0 + $1.size }
    }

    var presentCategories: [CleanerCategory] {
        CleanerCategory.allCases.filter { !items(in: $0).isEmpty }
    }
}

/// What the scan looks for and what it preselects. Mirrors the two knobs that
/// actually change the outcome — which types, and how stale an item must be.
struct CleanerPolicy: Codable, Sendable, Equatable {
    var enabledCategories: Set<CleanerCategory>
    /// Items touched more recently than this are found but left unchecked.
    var minimumAgeDays: Int
    /// Rows below this are folded into their category total instead of listed.
    var minimumItemBytes: UInt64

    static let `default` = CleanerPolicy(
        enabledCategories: Set(CleanerCategory.allCases.filter(\.selectedByDefault)),
        minimumAgeDays: 7,
        minimumItemBytes: 10 * 1024 * 1024
    )

    /// The initial checkbox state for a row: the category is on, and the item has
    /// been idle at least as long as the age limit.
    func preselects(_ item: CleanableItem) -> Bool {
        guard enabledCategories.contains(item.category) else { return false }
        guard minimumAgeDays > 0, let lastUsed = item.lastUsed else { return true }
        let days = Calendar.current.dateComponents([.day], from: lastUsed, to: Date()).day ?? 0
        return days >= minimumAgeDays
    }
}

/// The outcome of a removal pass, so the panel can report a real number rather
/// than the optimistic pre-scan estimate.
struct CleanerRemovalReport: Sendable {
    var bytesReclaimed: UInt64 = 0
    var itemsRemoved: Int = 0
    var failures: [(name: String, reason: String)] = []

    var summary: String {
        if itemsRemoved == 0 { return "Nothing was removed" }
        let size = ByteFormat.string(bytesReclaimed)
        let noun = itemsRemoved == 1 ? "item" : "items"
        if failures.isEmpty { return "Moved \(itemsRemoved) \(noun) to the Trash — \(size)" }
        return "Moved \(itemsRemoved) \(noun) — \(size), \(failures.count) skipped"
    }
}

enum ByteFormat {
    /// Decimal units, matching what Finder and About This Mac report. The old
    /// binary-unit formatter disagreed with the Finder figure next to it, which
    /// reads as a bug even when the math is right.
    static func string(_ bytes: UInt64) -> String {
        guard bytes > 0 else { return "Zero KB" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
