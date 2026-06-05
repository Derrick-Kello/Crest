//
//  CleanupService.swift
//  DiskPilot
//

import Foundation
import OSLog

enum CleanupServiceError: LocalizedError {
    case blockedPath(String)
    case unsupportedTarget
    case cleanupFailed(String)

    var errorDescription: String? {
        switch self {
        case .blockedPath(let path): "Cleanup blocked for protected path: \(path)"
        case .unsupportedTarget: "This target does not support automated cleanup"
        case .cleanupFailed(let reason): reason
        }
    }
}

final class CleanupService: Sendable {
    static let shared = CleanupService()

    private let logger = Logger(subsystem: "com.diskpilot", category: "Cleanup")
    private let fileManager = FileManager.default

    private let blockedPathFragments = [
        "/documents/",
        "/desktop/",
        "/pictures/",
        "/photos library",
        "/library/mobile documents/",
        "/icloud drive",
        "/system/",
        "/usr/",
        "/bin/",
        "/sbin/",
    ]

    func previewCleanup(for target: DeveloperCleanupTarget) -> UInt64 {
        DiskService.shared.directorySize(at: target.path)
    }

    func performCleanup(
        for target: DeveloperCleanupTarget,
        safetyLevel: CleanupSafetyLevel
    ) throws -> CleanupLogEntry {
        let resolved = expandTilde(target.path)
        try validatePath(resolved, safetyLevel: safetyLevel)

        let before = DiskService.shared.directorySize(at: resolved)
        guard let command = target.cleanupCommand else {
            throw CleanupServiceError.unsupportedTarget
        }

        switch command {
        case .deleteDirectory:
            try deleteDirectoryContents(at: resolved)
        case .shell(let shellCommand):
            _ = try ProcessRunner.runShell(shellCommand)
        }

        let after = DiskService.shared.directorySize(at: resolved)
        let reclaimed = before > after ? before - after : before

        let entry = CleanupLogEntry(
            timestamp: Date(),
            action: "Cleaned \(target.displayName)",
            path: resolved,
            bytesReclaimed: reclaimed,
            success: true
        )
        logger.info("Cleanup OK: \(target.displayName, privacy: .public) reclaimed \(reclaimed) bytes")
        return entry
    }

    func pruneDocker(aggressive: Bool = false) throws -> CleanupLogEntry {
        guard ProcessRunner.commandExists("docker") else {
            throw CleanupServiceError.cleanupFailed("Docker CLI not found")
        }
        let flag = aggressive ? " -a" : ""
        let output = try ProcessRunner.runShell("docker system prune -f\(flag)")
        let entry = CleanupLogEntry(
            timestamp: Date(),
            action: "Docker system prune",
            path: "docker",
            bytesReclaimed: 0,
            success: true
        )
        logger.info("Docker prune: \(output, privacy: .public)")
        return entry
    }

    // MARK: - Private

    private func validatePath(_ path: String, safetyLevel: CleanupSafetyLevel) throws {
        let normalized = path.lowercased()
        for fragment in blockedPathFragments {
            if normalized.contains(fragment) {
                throw CleanupServiceError.blockedPath(path)
            }
        }
        if safetyLevel == .conservative, normalized.contains(".android/avd") {
            throw CleanupServiceError.blockedPath(path)
        }
    }

    private func deleteDirectoryContents(at path: String) throws {
        let url = URL(fileURLWithPath: path)
        guard fileManager.fileExists(atPath: path) else { return }
        let children = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
        for child in children {
            try fileManager.removeItem(at: child)
        }
    }

    private func expandTilde(_ path: String) -> String {
        guard path.hasPrefix("~") else { return path }
        return fileManager.homeDirectoryForCurrentUser.path + String(path.dropFirst())
    }
}
