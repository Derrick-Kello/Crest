//
//  PathSafetyClassifier.swift
//  DiskPilot
//

import Foundation

/// Classifies paths as user-manageable vs macOS-protected so cleanup never touches OS-critical data.
enum PathSafetyClassifier {
    /// Paths or fragments that must never be deleted automatically.
    private static let dangerousFragments = [
        "/system/",
        "/system/volumes/",
        "/usr/",
        "/bin/",
        "/sbin/",
        "/private/var/db/",
        "/library/apple/",
        "/library/preferences/system",
        "/.ssh/",
        "/.gnupg/",
        "/library/keychains/",
        "/library/com.apple.bluetooth",
        "/library/com.apple.security",
        "/library/com.apple.networkextension",
    ]

    /// User data — never auto-delete; review only.
    private static let userDataFragments = [
        "/documents/",
        "/desktop/",
        "/pictures/",
        "/photos library",
        "/library/mobile documents/",
        "/icloud drive/",
        "/movies/",
        "/music/",
    ]

    static func riskLevel(for path: String, category: StorageFindingCategory) -> StorageRiskLevel {
        let normalized = path.lowercased()

        for fragment in dangerousFragments where normalized.contains(fragment) {
            return .dangerous
        }
        for fragment in userDataFragments where normalized.contains(fragment) {
            return .dangerous
        }

        switch category {
        case .xcode, .node, .logs, .systemCache:
            if normalized.contains("deriveddata")
                || normalized.contains("/caches/yarn")
                || normalized.contains("shipit")
                || normalized.contains("/caches/npm")
                || normalized.contains("swiftpm")
                || normalized.contains("/logs") {
                return .safe
            }
            if normalized.contains("devicesupport") || normalized.contains("/archives/") {
                return .caution
            }
            return .safe

        case .simulator:
            return normalized.contains("coresimulator") ? .caution : .safe

        case .docker:
            return .caution

        case .git:
            return .dangerous

        case .downloads, .media:
            return .caution

        case .appSupport:
            return .caution

        case .other:
            if normalized.contains("/.Trash") { return .caution }
            return .caution
        }
    }

    static func isCleanupAllowed(path: String, automated: Bool) -> Bool {
        let risk = riskLevel(for: path, category: .other)
        if risk == .dangerous { return false }
        if automated && risk == .caution {
            // Caution paths need explicit user confirmation in UI, not bulk auto-clean.
            return false
        }
        return true
    }

    static func isOSProtected(path: String) -> Bool {
        riskLevel(for: path, category: .other) == .dangerous
    }
}
