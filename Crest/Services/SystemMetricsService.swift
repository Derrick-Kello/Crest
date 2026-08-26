//
//  SystemMetricsService.swift
//  Crest
//

import Darwin
import Foundation

/// One sample of live machine state.
struct SystemMetrics: Sendable, Equatable {
    var cpuUser: Double = 0
    var cpuSystem: Double = 0
    var cpuIdle: Double = 100
    var coreCount: Int = 0

    var memoryTotal: UInt64 = 0
    var memoryApp: UInt64 = 0
    var memoryWired: UInt64 = 0
    var memoryCompressed: UInt64 = 0
    var memoryCached: UInt64 = 0
    var pressure: MemoryPressure = .normal

    var swapUsed: UInt64 = 0
    var swapTotal: UInt64 = 0

    var networkInPerSecond: UInt64 = 0
    var networkOutPerSecond: UInt64 = 0

    var loadAverage: [Double] = [0, 0, 0]
    var uptime: TimeInterval = 0

    /// Everything that isn't idle — what a user means by "CPU usage".
    var cpuUsed: Double { max(0, min(100, 100 - cpuIdle)) }

    /// Wired + app + compressed. Cached files are excluded because macOS hands
    /// that memory back on demand; counting it makes a healthy Mac look full.
    var memoryUsed: UInt64 { memoryApp + memoryWired + memoryCompressed }

    var memoryUsedFraction: Double {
        guard memoryTotal > 0 else { return 0 }
        return Double(memoryUsed) / Double(memoryTotal)
    }

    var formattedUptime: String {
        let days = Int(uptime) / 86400
        let hours = (Int(uptime) % 86400) / 3600
        let minutes = (Int(uptime) % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }
}

enum MemoryPressure: Int, Sendable, Comparable {
    case normal = 1
    case warning = 2
    case critical = 4

    var label: String {
        switch self {
        case .normal: "Normal"
        case .warning: "Elevated"
        case .critical: "Critical"
        }
    }

    static func < (lhs: MemoryPressure, rhs: MemoryPressure) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Reads CPU, memory, swap, and network counters straight from the kernel.
///
/// No subprocesses: shelling out to `top` or `vm_stat` to render a value that
/// updates every second would spawn a process per tick, which costs more than the
/// entire rest of this app. All of these are counters, so every rate here is a
/// delta between two samples held in `Sampler`.
nonisolated final class SystemMetricsService: Sendable {
    static let shared = SystemMetricsService()

    private let sampler = Sampler()

    func sample() -> SystemMetrics {
        var metrics = SystemMetrics()
        metrics.coreCount = ProcessInfo.processInfo.processorCount
        metrics.memoryTotal = ProcessInfo.processInfo.physicalMemory
        metrics.uptime = ProcessInfo.processInfo.systemUptime

        readCPU(into: &metrics)
        readMemory(into: &metrics)
        readSwap(into: &metrics)
        readNetwork(into: &metrics)

        var loads = [Double](repeating: 0, count: 3)
        if getloadavg(&loads, 3) == 3 { metrics.loadAverage = loads }

        return metrics
    }

    /// Forget the previous sample so the next one doesn't report a rate averaged
    /// over the whole time the panel was closed.
    func resetRates() {
        sampler.reset()
    }

    // MARK: - CPU

    private func readCPU(into metrics: inout SystemMetrics) {
        // The C macro HOST_CPU_LOAD_INFO_COUNT isn't imported into Swift, so the
        // struct's size in `integer_t` units is computed directly.
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        var info = host_cpu_load_info()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }

        let user = UInt64(info.cpu_ticks.0)
        let system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2)
        let nice = UInt64(info.cpu_ticks.3)

        guard let previous = sampler.exchangeCPU(user: user + nice, system: system, idle: idle) else {
            // First sample has no baseline; report idle rather than a bogus spike.
            return
        }

        let deltaUser = Double(user &+ nice &- previous.user)
        let deltaSystem = Double(system &- previous.system)
        let deltaIdle = Double(idle &- previous.idle)
        let total = deltaUser + deltaSystem + deltaIdle
        guard total > 0 else { return }

        metrics.cpuUser = deltaUser / total * 100
        metrics.cpuSystem = deltaSystem / total * 100
        metrics.cpuIdle = deltaIdle / total * 100
    }

    // MARK: - Memory

    private func readMemory(into metrics: inout SystemMetrics) {
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        var stats = vm_statistics64_data_t()
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }

        let pageSize = UInt64(vm_kernel_page_size)
        // `internal_page_count` is anonymous memory owned by apps; external pages
        // are file-backed and reclaimable, which is what Activity Monitor calls
        // "Cached Files".
        metrics.memoryApp = UInt64(stats.internal_page_count) * pageSize
        metrics.memoryWired = UInt64(stats.wire_count) * pageSize
        metrics.memoryCompressed = UInt64(stats.compressor_page_count) * pageSize
        metrics.memoryCached = UInt64(stats.external_page_count) * pageSize
        metrics.pressure = readPressure()
    }

    /// The kernel's own pressure level, the same signal macOS uses to decide when
    /// to start compressing and swapping. Far more meaningful than a used/total
    /// ratio, which on macOS is high almost all of the time by design.
    private func readPressure() -> MemoryPressure {
        var level: Int32 = 1
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else {
            return .normal
        }
        return MemoryPressure(rawValue: Int(level)) ?? .normal
    }

    private func readSwap(into metrics: inout SystemMetrics) {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return }
        metrics.swapUsed = usage.xsu_used
        metrics.swapTotal = usage.xsu_total
    }

    // MARK: - Network

    private func readNetwork(into metrics: inout SystemMetrics) {
        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0

        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return }
        defer { freeifaddrs(addresses) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }

            guard let addr = current.pointee.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_LINK) else { continue }

            let name = String(cString: current.pointee.ifa_name)
            // Loopback would double-count local traffic as real throughput.
            guard !name.hasPrefix("lo") else { continue }

            guard let data = current.pointee.ifa_data else { continue }
            let stats = data.assumingMemoryBound(to: if_data.self).pointee
            totalIn += UInt64(stats.ifi_ibytes)
            totalOut += UInt64(stats.ifi_obytes)
        }

        guard let previous = sampler.exchangeNetwork(in: totalIn, out: totalOut) else { return }
        let elapsed = max(previous.elapsed, 0.001)
        // Counters are 32-bit on some interfaces and wrap; a negative delta means
        // a wrap or an interface disappearing, so report zero instead of garbage.
        metrics.networkInPerSecond = totalIn > previous.in
            ? UInt64(Double(totalIn - previous.in) / elapsed) : 0
        metrics.networkOutPerSecond = totalOut > previous.out
            ? UInt64(Double(totalOut - previous.out) / elapsed) : 0
    }
}

/// Holds the previous counter reading so rates can be differenced. Locked because
/// sampling may happen from whichever task the timer lands on.
private final class Sampler: @unchecked Sendable {
    private struct CPUSample { let user: UInt64; let system: UInt64; let idle: UInt64 }
    private struct NetSample { let bytesIn: UInt64; let bytesOut: UInt64; let at: Date }

    private let lock = NSLock()
    private var cpu: CPUSample?
    private var net: NetSample?

    func exchangeCPU(user: UInt64, system: UInt64, idle: UInt64) -> (user: UInt64, system: UInt64, idle: UInt64)? {
        lock.lock(); defer { lock.unlock() }
        let previous = cpu
        cpu = CPUSample(user: user, system: system, idle: idle)
        guard let previous else { return nil }
        return (previous.user, previous.system, previous.idle)
    }

    func exchangeNetwork(in bytesIn: UInt64, out bytesOut: UInt64) -> (in: UInt64, out: UInt64, elapsed: TimeInterval)? {
        lock.lock(); defer { lock.unlock() }
        let previous = net
        let now = Date()
        net = NetSample(bytesIn: bytesIn, bytesOut: bytesOut, at: now)
        guard let previous else { return nil }
        return (previous.bytesIn, previous.bytesOut, now.timeIntervalSince(previous.at))
    }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        cpu = nil
        net = nil
    }
}
