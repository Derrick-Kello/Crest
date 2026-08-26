//
//  BrewModels.swift
//  Crest
//

import Foundation
import SwiftUI

/// A formula or a cask, installed or merely found by a search.
///
/// One type for both because the panel shows them in one list and every action —
/// install, upgrade, uninstall — differs only by the `--formula` / `--cask` flag.
struct BrewPackage: Identifiable, Hashable, Sendable {
    let name: String
    let isCask: Bool
    let summary: String
    let tap: String
    /// Nil when the package is a search hit that isn't on the Mac.
    let installedVersion: String?
    let latestVersion: String
    let isOutdated: Bool
    /// Bytes in the Cellar or Caskroom. Zero until sizing has run, which is a
    /// separate pass because it walks directories and the list has to appear first.
    var sizeOnDisk: UInt64 = 0
    /// Set when Homebrew flagged the package as pinned; upgrading it would fail.
    let isPinned: Bool

    var id: String { (isCask ? "cask:" : "formula:") + name }
    var isInstalled: Bool { installedVersion != nil }
    var kindLabel: String { isCask ? "Cask" : "Formula" }

    var versionLabel: String {
        guard let installedVersion else { return latestVersion }
        return isOutdated ? "\(installedVersion) → \(latestVersion)" : installedVersion
    }

    /// Third-party taps are the ones Homebrew now asks the user to trust, so the
    /// UI needs to be able to tell them apart from the official ones.
    var isThirdPartyTap: Bool {
        !tap.isEmpty && !tap.hasPrefix("homebrew/")
    }
}

/// Where Homebrew stands on this Mac.
enum BrewAvailability: Equatable, Sendable {
    case unknown
    case missing
    case ready(prefix: String)

    var isReady: Bool { if case .ready = self { return true }; return false }
}

/// What a running `brew` command is doing, in the words the user sees.
enum BrewPhase: String, Sendable {
    case preparing = "Working"
    case downloading = "Downloading files"
    case installing = "Installing files"
    case removing = "Removing files"
    case updating = "Updating files"
    case refreshing = "Refreshing list"

    var iconName: String {
        switch self {
        case .preparing, .refreshing: "arrow.triangle.2.circlepath"
        case .downloading: "arrow.down.circle"
        case .installing: "arrow.down.app"
        case .removing: "trash"
        case .updating: "arrow.up.circle"
        }
    }
}

/// A command in flight. Held as one value so the view has a single thing to show
/// or hide, rather than four booleans that can disagree with each other.
struct BrewOperation: Sendable, Equatable {
    let title: String
    var phase: BrewPhase = .preparing
    /// Nil while Homebrew hasn't reported a percentage — most of an install, in
    /// practice, so the bar is indeterminate rather than frozen at zero.
    var fraction: Double?
    var lastLine: String = ""
}

/// The reason a command stopped short, and what the user can do about it.
enum BrewFailure: Equatable, Sendable {
    /// Homebrew asked for an administrator password, which it can only do in a
    /// real terminal. The command is carried over so the user can finish it there.
    case needsTerminal(command: String)
    /// Homebrew refuses to use a third-party tap until it is trusted once.
    case untrustedTap(tap: String, command: String)
    case failed(message: String)
    case cancelled
}
