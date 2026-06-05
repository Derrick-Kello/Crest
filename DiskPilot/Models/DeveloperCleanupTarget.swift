//
//  DeveloperCleanupTarget.swift
//  DiskPilot
//

import Foundation

enum CleanupRiskLevel: String {
    case safe = "Safe"
    case moderate = "Moderate"

    var iconName: String {
        switch self {
        case .safe: "checkmark.shield"
        case .moderate: "exclamationmark.shield"
        }
    }
}

struct DeveloperCleanupTarget: Identifiable {
    let id: String
    let path: String
    let displayName: String
    let riskLevel: CleanupRiskLevel
    let cleanupCommand: CleanupCommand?
    var size: UInt64?

    var formattedSize: String {
        guard let size else { return "—" }
        return DiskUsageModel.formatBytes(size)
    }

    static let allTargets: [DeveloperCleanupTarget] = [
        DeveloperCleanupTarget(
            id: "xcode-derived",
            path: "~/Library/Developer/Xcode/DerivedData",
            displayName: "Xcode DerivedData",
            riskLevel: .safe,
            cleanupCommand: .deleteDirectory
        ),
        DeveloperCleanupTarget(
            id: "ios-simulator",
            path: "~/Library/Developer/CoreSimulator",
            displayName: "iOS Simulator (unavailable devices)",
            riskLevel: .moderate,
            cleanupCommand: .shell("xcrun simctl delete unavailable 2>/dev/null || true")
        ),
        DeveloperCleanupTarget(
            id: "npm-cache",
            path: "~/.npm",
            displayName: "npm Cache",
            riskLevel: .safe,
            cleanupCommand: .shell("npm cache clean --force 2>/dev/null || true")
        ),
        DeveloperCleanupTarget(
            id: "yarn-cache",
            path: "~/Library/Caches/Yarn",
            displayName: "Yarn Cache",
            riskLevel: .safe,
            cleanupCommand: .deleteDirectory
        ),
        DeveloperCleanupTarget(
            id: "swiftpm-cache",
            path: "~/Library/Caches/org.swift.swiftpm",
            displayName: "Swift Package Manager Cache",
            riskLevel: .safe,
            cleanupCommand: .deleteDirectory
        ),
        DeveloperCleanupTarget(
            id: "xcode-cache",
            path: "~/Library/Caches/com.apple.dt.Xcode",
            displayName: "Xcode Caches",
            riskLevel: .safe,
            cleanupCommand: .deleteDirectory
        ),
        DeveloperCleanupTarget(
            id: "shipit-vscode",
            path: "~/Library/Caches/com.microsoft.VSCode.ShipIt",
            displayName: "VS Code Updater Cache",
            riskLevel: .safe,
            cleanupCommand: .deleteDirectory
        ),
        DeveloperCleanupTarget(
            id: "homebrew-cache",
            path: "~/Library/Caches/Homebrew",
            displayName: "Homebrew Cache",
            riskLevel: .safe,
            cleanupCommand: .shell("brew cleanup -s 2>/dev/null || true")
        ),
        DeveloperCleanupTarget(
            id: "user-logs",
            path: "~/Library/Logs",
            displayName: "User Logs",
            riskLevel: .safe,
            cleanupCommand: .deleteDirectory
        ),
        DeveloperCleanupTarget(
            id: "gradle-cache",
            path: "~/.gradle/caches",
            displayName: "Gradle Cache",
            riskLevel: .safe,
            cleanupCommand: .deleteDirectory
        ),
        DeveloperCleanupTarget(
            id: "python-cache",
            path: "~/Library/Caches/pip",
            displayName: "Python pip Cache",
            riskLevel: .safe,
            cleanupCommand: .deleteDirectory
        ),
        DeveloperCleanupTarget(
            id: "android-avd",
            path: "~/.android/avd",
            displayName: "Android Emulator Storage",
            riskLevel: .moderate,
            cleanupCommand: nil
        ),
        DeveloperCleanupTarget(
            id: "empty-trash",
            path: "~/.Trash",
            displayName: "Trash",
            riskLevel: .moderate,
            cleanupCommand: .shell("osascript -e 'tell application \"Finder\" to empty trash' 2>/dev/null || true")
        ),
    ]

    static func target(forId id: String) -> DeveloperCleanupTarget? {
        allTargets.first { $0.id == id }
    }
}

enum CleanupCommand {
    case deleteDirectory
    case shell(String)
}
