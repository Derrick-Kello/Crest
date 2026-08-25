//
//  HomebrewService.swift
//  DiskPilot
//

import AppKit
import Foundation
import OSLog

/// Drives the `brew` command line and keeps the panel's view of it.
///
/// Homebrew is a package manager, not an API, so everything here is a subprocess.
/// Two rules follow from that and shape the whole file: nothing runs on the main
/// actor (a `brew upgrade` takes minutes), and no user-supplied string ever
/// reaches a shell — package names are validated and passed as argv elements, so
/// the only place a real shell is involved is the Terminal handoff, which the
/// user sees and confirms.
@MainActor
@Observable
final class HomebrewService {
    static let shared = HomebrewService()

    private let logger = Logger(subsystem: "com.diskpilot", category: "Homebrew")

    // MARK: - State

    private(set) var availability: BrewAvailability = .unknown
    private(set) var installed: [BrewPackage] = []
    private(set) var searchResults: [BrewPackage] = []
    private(set) var isLoading = false
    private(set) var isSearching = false
    private(set) var operation: BrewOperation?
    private(set) var failure: BrewFailure?
    /// What `brew cleanup` says it could free. Refreshed with the package list
    /// because it is the number that makes this section a disk feature.
    private(set) var reclaimableBytes: UInt64 = 0
    private(set) var lastRefresh: Date?

    private var token: ProcessToken?
    private var brewPath: String?
    private var searchTask: Task<Void, Never>?

    var outdated: [BrewPackage] { installed.filter { $0.isOutdated && !$0.isPinned } }
    var isBusy: Bool { operation != nil }

    private init() {}

    // MARK: - Discovery

    /// The two prefixes Homebrew actually uses — Apple silicon and Intel. Looking
    /// these up directly rather than searching `PATH` is deliberate: a menu-bar app
    /// launched at login inherits `launchd`'s environment, not the shell's, so
    /// `PATH` almost never contains `brew` even when it is plainly installed.
    private static let candidatePaths = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]

    private func locate() -> String? {
        if let brewPath, FileManager.default.isExecutableFile(atPath: brewPath) { return brewPath }
        let found = Self.candidatePaths.first { FileManager.default.isExecutableFile(atPath: $0) }
        brewPath = found
        return found
    }

    /// Environment for every invocation.
    ///
    /// `HOMEBREW_NO_AUTO_UPDATE` is the important one: without it a plain
    /// `brew outdated` silently spends half a minute refreshing every tap, and the
    /// panel appears hung. Updating is an explicit button instead.
    private func environment(for brew: String) -> [String: String] {
        let prefix = URL(fileURLWithPath: brew).deletingLastPathComponent().deletingLastPathComponent().path
        return [
            "PATH": "\(prefix)/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": NSHomeDirectory(),
            "HOMEBREW_NO_AUTO_UPDATE": "1",
            "HOMEBREW_NO_ENV_HINTS": "1",
            "HOMEBREW_NO_COLOR": "1",
            "HOMEBREW_NO_EMOJI": "1",
            "HOMEBREW_NO_INSTALL_CLEANUP": "1",
        ]
    }

    // MARK: - Loading

    func refresh() async {
        guard !isLoading, !isBusy else { return }
        guard let brew = locate() else {
            availability = .missing
            installed = []
            reclaimableBytes = 0
            return
        }
        availability = .ready(prefix: URL(fileURLWithPath: brew).deletingLastPathComponent().deletingLastPathComponent().path)

        isLoading = true
        defer { isLoading = false }

        let environment = environment(for: brew)
        let result = await ProcessRunner.stream(
            brew, arguments: ["info", "--json=v2", "--installed"], environment: environment
        )
        guard result.succeeded, let data = result.output.data(using: .utf8) else {
            logger.error("brew info failed: \(result.output, privacy: .public)")
            installed = []
            return
        }

        let parsed = await Task.detached(priority: .userInitiated) {
            BrewJSON.parseInstalled(data)
        }.value

        installed = parsed
        lastRefresh = .now
        await sizePackages(brewPrefix: URL(fileURLWithPath: brew).deletingLastPathComponent().deletingLastPathComponent().path)
        await refreshReclaimable(brew: brew, environment: environment)
    }

    /// Disk sizes are a second pass, off the main actor, because walking the Cellar
    /// for a hundred formulae takes longer than the list is worth waiting for.
    private func sizePackages(brewPrefix: String) async {
        let names = installed.map { (id: $0.id, name: $0.name, isCask: $0.isCask) }
        let sizes = await Task.detached(priority: .utility) { () -> [String: UInt64] in
            var result: [String: UInt64] = [:]
            for entry in names {
                let root = entry.isCask ? "\(brewPrefix)/Caskroom" : "\(brewPrefix)/Cellar"
                let url = URL(fileURLWithPath: root).appending(path: entry.name)
                guard FileManager.default.fileExists(atPath: url.path) else { continue }
                result[entry.id] = DiskService.shared.allocatedSize(at: url)
            }
            return result
        }.value

        for index in installed.indices {
            installed[index].sizeOnDisk = sizes[installed[index].id] ?? 0
        }
    }

    private func refreshReclaimable(brew: String, environment: [String: String]) async {
        let result = await ProcessRunner.stream(brew, arguments: ["cleanup", "-n"], environment: environment)
        reclaimableBytes = BrewJSON.parseFreeableBytes(result.output)
    }

    // MARK: - Search

    /// Debounced by the caller's cancellation of the previous task, so typing does
    /// not queue one `brew search` per keystroke.
    func search(_ query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2, let brew = locate() else {
            searchResults = []
            isSearching = false
            return
        }
        guard Self.isSafeName(trimmed) || trimmed.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else {
            searchResults = []
            return
        }

        isSearching = true
        let environment = environment(for: brew)
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled, let self else { return }

            async let formulae = ProcessRunner.stream(brew, arguments: ["search", "--formula", trimmed], environment: environment)
            async let casks = ProcessRunner.stream(brew, arguments: ["search", "--cask", trimmed], environment: environment)

            let names = BrewJSON.parseSearch(formula: await formulae.output, cask: await casks.output)
            guard !Task.isCancelled else { return }

            // Only the top hits get a details lookup: `brew info` on fifty names is
            // slower than the search itself and nothing below the fold is read.
            let wanted = Array(names.formulae.prefix(6)) + Array(names.casks.prefix(6))
            guard !wanted.isEmpty else {
                self.searchResults = []
                self.isSearching = false
                return
            }

            let info = await ProcessRunner.stream(
                brew, arguments: ["info", "--json=v2"] + wanted, environment: environment
            )
            guard !Task.isCancelled else { return }

            let installedIDs = Set(self.installed.map(\.id))
            if let data = info.output.data(using: .utf8) {
                let parsed = BrewJSON.parseInstalled(data, includeUninstalled: true)
                self.searchResults = parsed.filter { !installedIDs.contains($0.id) }
            } else {
                self.searchResults = []
            }
            self.isSearching = false
        }
    }

    func clearSearch() {
        searchTask?.cancel()
        searchResults = []
        isSearching = false
    }

    // MARK: - Operations

    func install(_ package: BrewPackage) async {
        await run(
            title: "Installing \(package.name)",
            arguments: ["install", package.isCask ? "--cask" : "--formula", package.name]
        )
    }

    func uninstall(_ package: BrewPackage) async {
        await run(
            title: "Uninstalling \(package.name)",
            arguments: ["uninstall", package.isCask ? "--cask" : "--formula", package.name]
        )
    }

    func upgrade(_ package: BrewPackage) async {
        await run(
            title: "Updating \(package.name)",
            arguments: ["upgrade", package.isCask ? "--cask" : "--formula", package.name]
        )
    }

    func upgradeAll() async {
        await run(title: "Updating packages", arguments: ["upgrade"])
    }

    /// `brew update` refreshes the catalog itself, which is the one command that is
    /// allowed to reach the network on its own schedule.
    func updateCatalog() async {
        await run(title: "Updating Homebrew", arguments: ["update"], phase: .refreshing)
    }

    func cleanup() async {
        await run(title: "Reclaiming space", arguments: ["cleanup", "-s"], phase: .removing)
    }

    func cancel() {
        token?.cancel()
    }

    private func run(title: String, arguments: [String], phase: BrewPhase = .preparing) async {
        guard !isBusy, let brew = locate() else { return }
        for argument in arguments where argument.hasPrefix("-") == false {
            guard Self.isSafeName(argument) else {
                failure = .failed(message: "\(argument) isn't a name Homebrew accepts.")
                return
            }
        }

        failure = nil
        operation = BrewOperation(title: title, phase: phase)
        let token = ProcessToken()
        self.token = token

        let progress = BrewProgressParser()
        let result = await ProcessRunner.stream(
            brew,
            arguments: arguments,
            environment: environment(for: brew),
            token: token
        ) { chunk in
            guard let update = progress.consume(chunk) else { return }
            Task { @MainActor [weak self] in
                guard var operation = self?.operation else { return }
                if let phase = update.phase { operation.phase = phase }
                if let fraction = update.fraction { operation.fraction = fraction }
                if let line = update.line { operation.lastLine = line }
                self?.operation = operation
            }
        }

        self.token = nil
        operation = nil

        if token.cancelled {
            failure = .cancelled
            return
        }
        if !result.succeeded {
            failure = Self.classify(output: result.output, brew: brew, arguments: arguments)
            logger.error("brew \(arguments.joined(separator: " "), privacy: .public) failed")
        }
        await refresh()
    }

    /// Reads the tail of a failed run and decides whether the user can do anything
    /// about it. Two failures are recoverable and worth naming: a command that
    /// needs a password, and a tap Homebrew wants confirmed. Everything else is
    /// reported as-is rather than paraphrased into something less useful.
    private static func classify(output: String, brew: String, arguments: [String]) -> BrewFailure {
        let command = ([brew] + arguments).map(shellQuote).joined(separator: " ")
        let lowered = output.lowercased()

        if let range = output.range(of: #"from untrusted tap ([A-Za-z0-9._-]+/[A-Za-z0-9._-]+)"#, options: .regularExpression) {
            let tap = String(output[range]).replacingOccurrences(of: "from untrusted tap ", with: "")
            return .untrustedTap(tap: tap, command: command)
        }
        if lowered.contains("a terminal is required")
            || lowered.contains("password is required")
            || lowered.contains("administrator privileges")
            || lowered.contains("sudo: no tty present") {
            return .needsTerminal(command: command)
        }

        let lines = output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let message = lines.last(where: { $0.lowercased().hasPrefix("error") }) ?? lines.last ?? "Homebrew reported no details."
        return .failed(message: String(message.prefix(300)))
    }

    func dismissFailure() {
        failure = nil
    }

    // MARK: - Terminal handoff

    /// Opens Terminal with the official installer. Homebrew's own installer is an
    /// interactive script that asks for a password and prints what it will do, so
    /// running it hidden inside this app would be both broken and rude.
    func openInstallerInTerminal() {
        runInTerminal(#"/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)""#)
    }

    /// Hands a command that needs a password over to Terminal, where macOS can
    /// prompt properly. DiskPilot never sees or handles the password.
    func continueInTerminal(_ command: String) {
        runInTerminal(command)
        failure = nil
    }

    private func runInTerminal(_ command: String) {
        let script = """
        tell application "Terminal"
            activate
            do script "\(appleScriptEscape(command))"
        end tell
        """
        Task.detached(priority: .userInitiated) {
            guard let apple = NSAppleScript(source: script) else { return }
            var error: NSDictionary?
            apple.executeAndReturnError(&error)
        }
    }

    private func appleScriptEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func shellQuote(_ value: String) -> String {
        // Already-safe tokens stay readable; anything else is single-quoted so the
        // command pasted into Terminal is exactly what ran here.
        if value.range(of: "^[A-Za-z0-9._+@/:=,-]+$", options: .regularExpression) != nil { return value }
        return "'" + value.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    /// Package names Homebrew itself accepts. Anything else never becomes argv.
    static func isSafeName(_ value: String) -> Bool {
        value.range(of: "^[A-Za-z0-9][A-Za-z0-9._+@/-]*$", options: .regularExpression) != nil
    }
}
