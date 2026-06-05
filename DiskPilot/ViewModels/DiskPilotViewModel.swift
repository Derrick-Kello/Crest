//
//  DiskPilotViewModel.swift
//  DiskPilot
//

import AppKit
import Foundation
import Observation
import SwiftUI

enum DashboardSection: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case storageFindings = "Storage Findings"
    case storageMap = "Storage Map"
    case developerCleanup = "Developer Cleanup"
    case docker = "Docker Manager"
    case systemInsights = "System Insights"
    case settings = "Settings"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .overview: "gauge.with.dots.needle.67percent"
        case .storageFindings: "list.bullet.rectangle.fill"
        case .storageMap: "chart.bar.fill"
        case .developerCleanup: "hammer.fill"
        case .docker: "shippingbox.fill"
        case .systemInsights: "waveform.path.ecg"
        case .settings: "gearshape.fill"
        }
    }
}

struct CleanupPreview: Identifiable {
    let id: String
    let target: DeveloperCleanupTarget
    let estimatedBytes: UInt64
}

private struct ScanResults {
    let diskUsage: DiskUsageModel
    let developerTargets: [DeveloperCleanupTarget]
    let dockerStats: DockerStats
    let notificationMessage: String?
}

@MainActor
@Observable
final class DiskPilotViewModel {
    var diskUsage: DiskUsageModel?
    var developerTargets: [DeveloperCleanupTarget] = DeveloperCleanupTarget.allTargets
    var dockerStats = DockerStats()
    var cleanupLog: [CleanupLogEntry] = []
    var selectedSection: DashboardSection = .overview
    var isScanning = false
    var lastScanDate: Date?
    var errorMessage: String?
    var showErrorAlert = false
    var cleanupPreview: CleanupPreview?
    var showCleanupConfirmation = false
    var notificationMessage: String?
    var deepScanResult: DeepScanResult?
    var isDeepScanning = false

    var menuBarEnabled: Bool
    var autoScanIntervalSeconds: Int
    var safetyLevel: CleanupSafetyLevel
    var dockerIntegrationEnabled: Bool

    private var refreshTask: Task<Void, Never>?
    private var activeScanTask: Task<Void, Never>?
    private var hasStartedRefreshLoop = false

    private let diskService = DiskService.shared
    private let deepScanService = DeepScanService.shared
    private let cleanupService = CleanupService.shared
    private let dockerService = DockerService.shared

    var isCriticallyLowOnSpace: Bool {
        deepScanResult?.isCriticallyLowOnSpace
            ?? (diskUsage.map { $0.percentageFree < 5 } ?? false)
    }

    var topSafeReclaimableBytes: UInt64 {
        deepScanResult?.findings
            .filter { $0.riskLevel == .safe && $0.cleanupTargetId != nil }
            .map(\.size)
            .reduce(0, +) ?? 0
    }

    var healthStatus: DiskHealthStatus {
        guard let diskUsage else { return .healthy }
        return DiskHealthStatus.fromFreePercentage(diskUsage.percentageFree)
    }

    var menuBarTitle: String {
        guard let diskUsage else { return "DiskPilot" }
        return "\(diskUsage.formattedFreeSpace) Free"
    }

    init() {
        let stored = AppSettingsStorage.load()
        menuBarEnabled = stored.menuBarEnabled
        autoScanIntervalSeconds = stored.autoScanIntervalSeconds
        safetyLevel = stored.safetyLevel
        dockerIntegrationEnabled = stored.dockerIntegrationEnabled
    }

    func persistSettings() {
        AppSettingsStorage.save(
            menuBarEnabled: menuBarEnabled,
            autoScanIntervalSeconds: autoScanIntervalSeconds,
            safetyLevel: safetyLevel,
            dockerIntegrationEnabled: dockerIntegrationEnabled
        )
    }

    func bootstrapIfNeeded() {
        startPeriodicRefreshIfNeeded()
        Task {
            if diskUsage == nil {
                await runScan()
            }
            if deepScanResult == nil {
                await runDeepScan()
            }
        }
    }

    func runDeepScan() async {
        guard !isDeepScanning else { return }
        isDeepScanning = true
        let result = await deepScanService.runDeepScan()
        deepScanResult = result
        isDeepScanning = false
        if result.isCriticallyLowOnSpace {
            notificationMessage = "Critical: only \(result.formattedFreeSpace) free"
        } else if topSafeReclaimableBytes > 500 * 1024 * 1024 {
            notificationMessage = "Safe cleanup can reclaim \(DiskUsageModel.formatBytes(topSafeReclaimableBytes))"
        }
    }

    func startPeriodicRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let interval = max(60, self.autoScanIntervalSeconds)
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                await self.runScan()
            }
        }
    }

    private func startPeriodicRefreshIfNeeded() {
        guard !hasStartedRefreshLoop else { return }
        hasStartedRefreshLoop = true
        startPeriodicRefresh()
    }

    func runScan() async {
        if let activeScanTask {
            await activeScanTask.value
            return
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performScan()
        }
        activeScanTask = task
        await task.value
        activeScanTask = nil
    }

    private func performScan() async {
        guard !isScanning else { return }

        isScanning = true

        do {
            let usage = try await diskService.scanDisk()
            let targets = await loadDeveloperTargets()
            let docker: DockerStats
            if dockerIntegrationEnabled {
                docker = await dockerService.fetchStats()
            } else {
                docker = await MainActor.run { self.dockerStats }
            }
            let notification = makeNotification(targets: targets, docker: docker)
            let results = ScanResults(
                diskUsage: usage,
                developerTargets: targets,
                dockerStats: docker,
                notificationMessage: notification
            )
            await applyScanResults(results)
            // Only kick off a deep scan when we don't already have one AND it's not running.
            // The bootstrap path and explicit user actions handle the first deep scan.
            if deepScanResult == nil && !isDeepScanning {
                Task { await runDeepScan() }
            }
        } catch {
            await reportError(error.localizedDescription)
        }
    }

    private func loadDeveloperTargets() async -> [DeveloperCleanupTarget] {
        let targets = DeveloperCleanupTarget.allTargets
        return await withTaskGroup(of: (Int, DeveloperCleanupTarget).self, returning: [DeveloperCleanupTarget].self) { group in
            for (index, target) in targets.enumerated() {
                group.addTask {
                    var copy = target
                    let path = target.path
                    // allocatedSize is a pure-Swift walk — no subprocess needed.
                    copy.size = DiskService.shared.directorySize(at: path)
                    return (index, copy)
                }
            }
            var indexed: [(Int, DeveloperCleanupTarget)] = []
            for await pair in group {
                indexed.append(pair)
            }
            return indexed.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    private func makeNotification(
        targets: [DeveloperCleanupTarget],
        docker: DockerStats
    ) -> String? {
        let cacheTotal = targets
            .filter { $0.id.contains("cache") || $0.id.contains("npm") || $0.id.contains("gradle") }
            .compactMap(\.size)
            .reduce(0, +)
        if cacheTotal > 10 * 1024 * 1024 * 1024 {
            return "Developer caches exceed 10 GB"
        }
        if docker.reclaimableSize > 3 * 1024 * 1024 * 1024 {
            return "Docker reclaimable: \(docker.formattedReclaimable)"
        }
        return nil
    }

    private func applyScanResults(_ results: ScanResults) async {
        diskUsage = results.diskUsage
        developerTargets = results.developerTargets
        dockerStats = results.dockerStats
        notificationMessage = results.notificationMessage
        isScanning = false
        lastScanDate = Date()
    }

    private func reportError(_ message: String) async {
        errorMessage = message
        showErrorAlert = true
        isScanning = false
    }

    // MARK: - Removed updateOnMainQueue helper
    // The class is @MainActor so all mutations are already on the main actor.
    // Direct assignment is safe everywhere inside this class.

    func dismissError() {
        errorMessage = nil
        showErrorAlert = false
    }

    func openDashboard() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.isVisible }) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    func requestCleanup(for target: DeveloperCleanupTarget) {
        let estimated = cleanupService.previewCleanup(for: target)
        cleanupPreview = CleanupPreview(id: target.id, target: target, estimatedBytes: estimated)
        showCleanupConfirmation = true
    }

    func confirmCleanup() async {
        guard let preview = cleanupPreview else { return }
        showCleanupConfirmation = false
        do {
            let entry = try cleanupService.performCleanup(
                for: preview.target,
                safetyLevel: safetyLevel
            )
            cleanupLog.insert(entry, at: 0)
            notificationMessage = "Freed \(DiskUsageModel.formatBytes(entry.bytesReclaimed))"
            cleanupPreview = nil
            await runScan()
            await runDeepScan()
        } catch {
            cleanupPreview = nil
            await reportError(error.localizedDescription)
        }
    }

    func quickCleanDeveloperCaches() async {
        for target in developerTargets where target.riskLevel == .safe && target.cleanupCommand != nil {
            _ = try? cleanupService.performCleanup(for: target, safetyLevel: safetyLevel)
        }
        await runScan()
    }

    func pruneDocker() async {
        do {
            let entry = try cleanupService.pruneDocker(aggressive: safetyLevel == .aggressive)
            cleanupLog.insert(entry, at: 0)
            notificationMessage = "Docker prune completed"
            if dockerIntegrationEnabled {
                let stats = await dockerService.fetchStats()
                dockerStats = stats
            }
        } catch {
            await reportError(error.localizedDescription)
        }
    }

    func refreshDockerStats() async {
        guard dockerIntegrationEnabled else { return }
        let stats = await dockerService.fetchStats()
        dockerStats = stats
    }
}
