//
//  ProcessRunner.swift
//  DiskPilot
//

import Foundation

enum ProcessRunnerError: LocalizedError {
    case failed(String)
    case commandNotFound(String)

    var errorDescription: String? {
        switch self {
        case .failed(let message): message
        case .commandNotFound(let cmd): "\(cmd) not found"
        }
    }
}

enum ProcessRunner {
    // Cache for commandExists lookups — avoids spawning a shell process on every scan.
    private static let commandExistsCache = CommandExistsCache()

    static func run(_ launchPath: String, arguments: [String] = []) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            let message = errorOutput.isEmpty ? output : errorOutput
            throw ProcessRunnerError.failed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return output
    }

    static func runShell(_ command: String) throws -> String {
        try run("/bin/zsh", arguments: ["-lc", command])
    }

    /// Thread-safe cached lookup — spawns a process only on first call per command name.
    static func commandExists(_ name: String) -> Bool {
        commandExistsCache.exists(name)
    }
}

// MARK: - Command existence cache

/// NSLock-guarded dictionary so commandExists is safe to call from concurrent Tasks.
private final class CommandExistsCache: @unchecked Sendable {
    private var cache: [String: Bool] = [:]
    private let lock = NSLock()

    func exists(_ name: String) -> Bool {
        lock.lock()
        if let cached = cache[name] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        // Resolve using execvp-style lookup via /usr/bin/which — no shell needed.
        let result = checkViaWhich(name)

        lock.lock()
        cache[name] = result
        lock.unlock()
        return result
    }

    private func checkViaWhich(_ name: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
