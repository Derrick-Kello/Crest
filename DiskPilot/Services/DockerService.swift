//
//  DockerService.swift
//  DiskPilot
//

import Foundation

nonisolated final class DockerService: Sendable {
    static let shared = DockerService()

    func fetchStats() async -> DockerStats {
        guard ProcessRunner.commandExists("docker") else {
            return DockerStats(isDockerAvailable: false)
        }
        do {
            let output = try ProcessRunner.runShell("docker system df 2>/dev/null")
            return parseDockerDF(output)
        } catch {
            return DockerStats(isDockerAvailable: false, rawOutput: error.localizedDescription)
        }
    }

    private func parseDockerDF(_ output: String) -> DockerStats {
        var stats = DockerStats(isDockerAvailable: true, rawOutput: output)
        let lines = output.split(separator: "\n").map(String.init)
        for line in lines {
            let lower = line.lowercased()
            let size = extractSize(from: line)
            if lower.hasPrefix("images") {
                stats.imagesSize = size.total
                stats.reclaimableSize += size.reclaimable
            } else if lower.hasPrefix("containers") {
                stats.containersSize = size.total
                stats.reclaimableSize += size.reclaimable
            } else if lower.hasPrefix("local volumes") || lower.hasPrefix("volumes") {
                stats.volumesSize = size.total
                stats.reclaimableSize += size.reclaimable
            }
        }
        return stats
    }

    private func extractSize(from line: String) -> (total: UInt64, reclaimable: UInt64) {
        let parts = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard parts.count >= 2 else { return (0, 0) }
        let total = parseHumanSize(parts[1])
        let reclaimable = parts.count > 3 ? parseHumanSize(parts[3]) : 0
        return (total, reclaimable)
    }

    private func parseHumanSize(_ value: String) -> UInt64 {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != "0" else { return 0 }
        let numberPart = trimmed.filter { $0.isNumber || $0 == "." }
        let unit = trimmed.filter { $0.isLetter }.uppercased()
        let number = Double(numberPart) ?? 0
        let multiplier: Double
        switch unit {
        case "TB": multiplier = 1024 * 1024 * 1024 * 1024
        case "GB": multiplier = 1024 * 1024 * 1024
        case "MB": multiplier = 1024 * 1024
        case "KB", "KIB": multiplier = 1024
        case "B": multiplier = 1
        default: multiplier = 1024 * 1024 * 1024
        }
        return UInt64(number * multiplier)
    }
}
