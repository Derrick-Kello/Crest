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

// MARK: - Streaming

/// Handle on a running process so a long operation can be cancelled from the UI.
///
/// Cancellation can arrive before the process has even started, so this records
/// the intent and `adopt` refuses the process rather than leaving an orphan
/// running with nothing left to stop it.
final class ProcessToken: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var isCancelled = false

    init() {}

    var cancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return isCancelled
    }

    /// Returns false when cancellation already happened, meaning the caller should
    /// not run the process at all.
    fileprivate func adopt(_ candidate: Process) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !isCancelled else { return false }
        process = candidate
        return true
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let running = process
        process = nil
        lock.unlock()
        running?.terminate()
    }

    fileprivate func release() {
        lock.lock(); defer { lock.unlock() }
        process = nil
    }
}

extension ProcessRunner {
    struct StreamResult: Sendable {
        let status: Int32
        let output: String

        var succeeded: Bool { status == 0 }
    }

    /// Runs a command and hands each chunk of output over as it arrives.
    ///
    /// `run` above buffers everything until the process exits, which is fine for a
    /// command that answers in milliseconds and useless for `brew upgrade`, where
    /// the output *is* the progress. stdout and stderr share one pipe deliberately:
    /// brew writes its progress to stderr and its results to stdout, and the user
    /// wants to read them interleaved in the order they happened.
    static func stream(
        _ launchPath: String,
        arguments: [String],
        environment: [String: String]? = nil,
        token: ProcessToken? = nil,
        onOutput: (@Sendable (String) -> Void)? = nil
    ) async -> StreamResult {
        await withCheckedContinuation { continuation in
            // A dedicated queue, not a Task: the read loop below blocks, and blocking
            // a cooperative-pool thread starves every other await in the app.
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: launchPath)
                process.arguments = arguments
                if let environment { process.environment = environment }

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                process.standardInput = FileHandle.nullDevice

                if let token, !token.adopt(process) {
                    continuation.resume(returning: StreamResult(status: -1, output: ""))
                    return
                }

                do {
                    try process.run()
                } catch {
                    token?.release()
                    continuation.resume(returning: StreamResult(status: -1, output: error.localizedDescription))
                    return
                }

                var collected = ""
                let handle = pipe.fileHandleForReading
                while true {
                    let data = handle.availableData
                    if data.isEmpty { break }
                    guard let chunk = String(data: data, encoding: .utf8) else { continue }
                    collected += chunk
                    onOutput?(chunk)
                }

                process.waitUntilExit()
                token?.release()
                continuation.resume(returning: StreamResult(status: process.terminationStatus, output: collected))
            }
        }
    }
}
