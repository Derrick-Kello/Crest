//
//  NetworkService.swift
//  Crest
//

import AppKit
import Darwin
import Foundation
import SystemConfiguration

/// Throughput at one instant, plus what this session has moved in total.
struct NetworkReading: Sendable, Equatable {
    var downloadPerSecond: UInt64 = 0
    var uploadPerSecond: UInt64 = 0
    var sessionDownload: UInt64 = 0
    var sessionUpload: UInt64 = 0
    /// Newest last. Bytes per second, for the sparkline.
    var downloadHistory: [Double] = []
    var uploadHistory: [Double] = []
    /// False until two samples exist, so the panel can say "Measuring" instead of
    /// showing a confident zero.
    var hasRate = false

    var peak: Double {
        max(downloadHistory.max() ?? 0, uploadHistory.max() ?? 0)
    }
}

struct NetworkInterfaceInfo: Identifiable, Sendable, Equatable {
    let name: String
    let displayName: String
    let ipv4: String?
    let isUp: Bool
    let bytesIn: UInt64
    let bytesOut: UInt64

    var id: String { name }
}

/// One process's share of the traffic over the last sampling window.
struct NetworkAppUsage: Identifiable, Sendable, Equatable {
    let pid: Int32
    let name: String
    let bytesIn: UInt64
    let bytesOut: UInt64
    /// Path to the owning app bundle, when the process belongs to one, so the row
    /// can show the real icon rather than a generic glyph.
    let bundlePath: String?

    var id: Int32 { pid }
    var total: UInt64 { bytesIn + bytesOut }
}

/// Live network throughput, per interface and per app.
///
/// Rates come from the kernel's own interface counters — the same numbers
/// `netstat -ib` prints — differenced between samples. Per-app figures need
/// `nettop`, because macOS keeps no per-process byte counter a plain API can read;
/// that subprocess only runs while the Network tab is actually on screen.
@MainActor
@Observable
final class NetworkService {
    static let shared = NetworkService()

    private(set) var reading = NetworkReading()
    private(set) var interfaces: [NetworkInterfaceInfo] = []
    private(set) var apps: [NetworkAppUsage] = []
    private(set) var isSamplingApps = false
    /// Set once nettop has answered at least once, so an empty list reads as
    /// "nothing is using the network" rather than "this hasn't run yet".
    private(set) var hasAppSample = false

    /// Pseudo-interfaces. AirDrop, VPN tunnels, bridges and virtual-machine links
    /// all carry copies of traffic that is already counted on the physical
    /// interface underneath, so including them double-counts a download.
    private static let ignoredPrefixes = ["lo", "awdl", "llw", "utun", "bridge", "anpi", "vmenet", "gif", "stf", "ipsec", "ppp"]

    private var previous: (bytesIn: UInt64, bytesOut: UInt64, at: Date)?
    private var tickTask: Task<Void, Never>?
    private var appTask: Task<Void, Never>?
    private var displayNames: [String: String] = [:]
    private let historyLength = 60

    private init() {}

    // MARK: - Lifecycle

    /// Sampling follows visibility. The Network tab is the only thing that reads
    /// these numbers, so nothing runs while it is closed.
    func setActive(_ active: Bool) {
        active ? start() : stop()
    }

    private func start() {
        guard tickTask == nil else { return }
        displayNames = Self.loadDisplayNames()
        // Drop the stale baseline so the first rate after reopening isn't averaged
        // over however long the panel was shut.
        previous = nil
        sample()

        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                self.sample()
            }
        }
        startAppSampling()
    }

    private func stop() {
        tickTask?.cancel()
        tickTask = nil
        appTask?.cancel()
        appTask = nil
        isSamplingApps = false
        previous = nil
        reading.hasRate = false
    }

    // MARK: - Interface counters

    private func sample() {
        let counters = Self.readCounters()
        interfaces = counters.interfaces
            .map { info in
                NetworkInterfaceInfo(
                    name: info.name,
                    displayName: displayNames[info.name] ?? info.name,
                    ipv4: info.ipv4,
                    isUp: info.isUp,
                    bytesIn: info.bytesIn,
                    bytesOut: info.bytesOut
                )
            }
            // Interfaces that have moved nothing and hold no address are noise.
            .filter { $0.ipv4 != nil || $0.bytesIn > 0 || $0.bytesOut > 0 }
            .sorted { ($0.bytesIn + $0.bytesOut) > ($1.bytesIn + $1.bytesOut) }

        let now = Date()
        defer { previous = (counters.totalIn, counters.totalOut, now) }
        guard let previous else { return }

        let elapsed = max(now.timeIntervalSince(previous.at), 0.001)
        // A counter that went backwards means an interface disappeared or a 32-bit
        // counter wrapped. Reporting zero beats reporting a fabricated gigabyte.
        let deltaIn = counters.totalIn > previous.bytesIn ? counters.totalIn - previous.bytesIn : 0
        let deltaOut = counters.totalOut > previous.bytesOut ? counters.totalOut - previous.bytesOut : 0

        reading.downloadPerSecond = UInt64(Double(deltaIn) / elapsed)
        reading.uploadPerSecond = UInt64(Double(deltaOut) / elapsed)
        reading.sessionDownload += deltaIn
        reading.sessionUpload += deltaOut
        reading.hasRate = true

        reading.downloadHistory.append(Double(reading.downloadPerSecond))
        reading.uploadHistory.append(Double(reading.uploadPerSecond))
        if reading.downloadHistory.count > historyLength { reading.downloadHistory.removeFirst() }
        if reading.uploadHistory.count > historyLength { reading.uploadHistory.removeFirst() }
    }

    private struct RawInterface {
        let name: String
        var ipv4: String?
        var isUp: Bool
        var bytesIn: UInt64
        var bytesOut: UInt64
    }

    /// One walk of `getifaddrs` collects both the link-layer byte counters and the
    /// IPv4 address, which arrive as separate entries for the same interface.
    private static func readCounters() -> (totalIn: UInt64, totalOut: UInt64, interfaces: [RawInterface]) {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return (0, 0, []) }
        defer { freeifaddrs(addresses) }

        var byName: [String: RawInterface] = [:]
        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            defer { cursor = current.pointee.ifa_next }
            let name = String(cString: current.pointee.ifa_name)
            guard !ignoredPrefixes.contains(where: { name.hasPrefix($0) }) else { continue }
            guard let addr = current.pointee.ifa_addr else { continue }

            var entry = byName[name] ?? RawInterface(name: name, ipv4: nil, isUp: false, bytesIn: 0, bytesOut: 0)
            entry.isUp = entry.isUp || (current.pointee.ifa_flags & UInt32(IFF_RUNNING)) != 0

            switch Int32(addr.pointee.sa_family) {
            case AF_LINK:
                guard let data = current.pointee.ifa_data else { break }
                let stats = data.assumingMemoryBound(to: if_data.self).pointee
                entry.bytesIn = UInt64(stats.ifi_ibytes)
                entry.bytesOut = UInt64(stats.ifi_obytes)
                totalIn += UInt64(stats.ifi_ibytes)
                totalOut += UInt64(stats.ifi_obytes)

            case AF_INET:
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let length = socklen_t(addr.pointee.sa_len)
                if getnameinfo(addr, length, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    entry.ipv4 = String(cString: host)
                }

            default:
                break
            }
            byName[name] = entry
        }

        return (totalIn, totalOut, Array(byName.values))
    }

    /// "en0" means nothing to anyone; SystemConfiguration knows it as "Wi-Fi".
    private static func loadDisplayNames() -> [String: String] {
        guard let all = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else { return [:] }
        var result: [String: String] = [:]
        for interface in all {
            guard let bsd = SCNetworkInterfaceGetBSDName(interface) as String? else { continue }
            result[bsd] = SCNetworkInterfaceGetLocalizedDisplayName(interface) as String? ?? bsd
        }
        return result
    }

    // MARK: - Per-app usage

    private func startAppSampling() {
        guard appTask == nil else { return }
        appTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.isSamplingApps = self.apps.isEmpty && !self.hasAppSample
                let sampled = await Self.sampleApps()
                guard !Task.isCancelled else { return }
                self.apps = sampled
                self.hasAppSample = true
                self.isSamplingApps = false
                // nettop's own window is a second; leaving a gap keeps this to a
                // couple of percent of one core rather than a permanent process.
                try? await Task.sleep(for: .seconds(4))
            }
        }
    }

    /// Two nettop samples, differenced. nettop reports cumulative totals per
    /// process, so the first block alone would rank whichever browser has been
    /// open longest rather than whatever is downloading right now.
    private static func sampleApps() async -> [NetworkAppUsage] {
        let result = await ProcessRunner.stream(
            "/usr/bin/nettop",
            arguments: ["-P", "-x", "-L", "2", "-J", "bytes_in,bytes_out", "-t", "wifi", "-t", "wired"],
            environment: ["PATH": "/usr/bin:/bin", "HOME": NSHomeDirectory()]
        )
        guard result.succeeded else { return [] }

        let blocks = NettopParser.parse(result.output)
        guard let latest = blocks.last, blocks.count > 1, let earlier = blocks.first else { return [] }

        var usage: [NetworkAppUsage] = []
        for (pid, current) in latest {
            let base = earlier[pid]
            let deltaIn = current.bytesIn > (base?.bytesIn ?? 0) ? current.bytesIn - (base?.bytesIn ?? 0) : 0
            let deltaOut = current.bytesOut > (base?.bytesOut ?? 0) ? current.bytesOut - (base?.bytesOut ?? 0) : 0
            guard deltaIn + deltaOut > 0 else { continue }

            // nettop truncates process names to fifteen characters, so a running
            // app is asked for its real name instead of showing "Brave Browser H".
            let running = NSRunningApplication(processIdentifier: pid)
            usage.append(NetworkAppUsage(
                pid: pid,
                name: running?.localizedName ?? current.name,
                bytesIn: deltaIn,
                bytesOut: deltaOut,
                bundlePath: running?.bundleURL?.path
            ))
        }

        return usage.sorted { $0.total > $1.total }
    }
}

/// Reads nettop's CSV-ish output.
///
/// Each sample begins with a header line and lists one row per process as
/// `name.pid,bytes_in,bytes_out,`. The name may itself contain dots, so the pid is
/// taken from the last one.
enum NettopParser {
    struct Row {
        let name: String
        let bytesIn: UInt64
        let bytesOut: UInt64
    }

    static func parse(_ output: String) -> [[Int32: Row]] {
        var blocks: [[Int32: Row]] = []
        var current: [Int32: Row] = [:]

        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            if trimmed.hasPrefix(",") || trimmed.hasPrefix("time") {
                // A header starts a new sample; the previous one is complete.
                if !current.isEmpty { blocks.append(current) }
                current = [:]
                continue
            }

            let fields = trimmed.components(separatedBy: ",")
            guard fields.count >= 3,
                  let bytesIn = UInt64(fields[1]),
                  let bytesOut = UInt64(fields[2])
            else { continue }

            let identifier = fields[0]
            guard let separator = identifier.lastIndex(of: "."),
                  let pid = Int32(identifier[identifier.index(after: separator)...])
            else { continue }

            current[pid] = Row(
                name: String(identifier[..<separator]),
                bytesIn: bytesIn,
                bytesOut: bytesOut
            )
        }

        if !current.isEmpty { blocks.append(current) }
        return blocks
    }
}

/// Per-second figures read differently from sizes: "1.2 MB/s" wants one decimal
/// and a stable width, which `ByteCountFormatter` will not give.
enum RateFormat {
    static func perSecond(_ bytesPerSecond: UInt64) -> String {
        "\(string(bytesPerSecond))/s"
    }

    static func string(_ bytes: UInt64) -> String {
        let value = Double(bytes)
        switch value {
        case ..<1_000: return "\(bytes) B"
        case ..<1_000_000: return String(format: "%.0f KB", value / 1_000)
        case ..<1_000_000_000: return String(format: "%.1f MB", value / 1_000_000)
        default: return String(format: "%.2f GB", value / 1_000_000_000)
        }
    }
}
