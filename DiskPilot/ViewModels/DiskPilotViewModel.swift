//
//  DiskPilotViewModel.swift
//  DiskPilot
//

import AppKit
import Foundation
import Observation
import SwiftUI

/// The sections stacked in the menu-bar panel, in display order.
enum PanelSection: String, CaseIterable, Identifiable, Codable {
    case system = "System"
    case disk = "Disk"
    case cleaner = "Cleaner"
    case power = "Power"
    case tools = "Tools"
    case clipboard = "Clipboard"
    case largeFolders = "Large folders"
    case docker = "Docker"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .system: "gauge.with.dots.needle.67percent"
        case .disk: "internaldrive"
        case .cleaner: "sparkles"
        case .power: "bolt"
        case .tools: "wrench.and.screwdriver"
        case .clipboard: "doc.on.clipboard"
        case .largeFolders: "chart.bar"
        case .docker: "shippingbox"
        }
    }
}

struct LargeFolder: Identifiable, Sendable {
    var id: String { path }
    let path: String
    let name: String
    let size: UInt64

    var formattedSize: String { ByteFormat.string(size) }
}

@MainActor
@Observable
final class DiskPilotViewModel {

    // MARK: - Disk

    var volume = VolumeSnapshot()

    var health: DiskHealthStatus {
        DiskHealthStatus.fromFreePercentage(volume.percentageFree)
    }

    var menuBarTitle: String {
        switch menuBarMetric {
        case .freeSpace: volume.totalCapacity == 0 ? "—" : volume.formattedFree
        case .cpu: "\(Int(metrics.cpuUsed.rounded()))%"
        case .memory: "\(Int((metrics.memoryUsedFraction * 100).rounded()))%"
        case .battery: power.hasBattery ? "\(power.percentage)%" : volume.formattedFree
        case .none: ""
        }
    }

    // MARK: - Cleaner

    var policy = CleanerPolicy.default
    var scan: CleanerScanResult?
    var isScanning = false
    var scanProgress = CleanerProgress(category: nil, detail: "", fraction: 0)
    var selectedItemIDs: Set<String> = []
    var isRemoving = false
    var lastReport: CleanerRemovalReport?
    var expandedCategories: Set<CleanerCategory> = []

    /// Bytes the user has actually ticked — the number the primary button promises.
    var selectedBytes: UInt64 {
        guard let scan else { return 0 }
        return scan.items.filter { selectedItemIDs.contains($0.id) }.reduce(0) { $0 + $1.size }
    }

    var selectedCount: Int { selectedItemIDs.count }

    var selectionIncludesPermanentRemoval: Bool {
        guard let scan else { return false }
        return scan.items.contains { selectedItemIDs.contains($0.id) && $0.category.removalIsPermanent }
    }

    // MARK: - System, power, tools

    var metrics = SystemMetrics()
    var power = PowerInfo()
    var lastPickedColor: String?

    let keepAwake = KeepAwakeService.shared
    let clipboard = ClipboardService.shared
    let colorPicker = ColorPickerService.shared

    private var metricsTask: Task<Void, Never>?

    // MARK: - Other sections

    var largeFolders: [LargeFolder] = []
    var isLoadingLargeFolders = false

    var dockerStats = DockerStats()
    var isLoadingDocker = false

    // MARK: - Chrome

    var collapsedSections: Set<PanelSection> = []
    var showSettings = false
    var statusMessage: String?
    var errorMessage: String?

    private var refreshTask: Task<Void, Never>?
    private let diskService = DiskService.shared
    private let cleanerService = CleanerService.shared
    private let dockerService = DockerService.shared

    // MARK: - Settings

    var launchAtLogin: Bool { didSet { Preferences.launchAtLogin = launchAtLogin } }
    var showFreeSpaceInMenuBar: Bool { didSet { Preferences.showFreeSpaceInMenuBar = showFreeSpaceInMenuBar } }
    var dockerIntegrationEnabled: Bool { didSet { Preferences.dockerEnabled = dockerIntegrationEnabled } }
    var menuBarMetric: MenuBarMetric { didSet { Preferences.menuBarMetric = menuBarMetric } }
    var commandBarEnabled: Bool {
        didSet {
            Preferences.commandBarEnabled = commandBarEnabled
            registerCommandBarHotKey()
        }
    }
    var commandBarHotKey: HotKeyCombo {
        didSet {
            Preferences.commandBarHotKey = commandBarHotKey
            registerCommandBarHotKey()
        }
    }
    private(set) var hotKeyRegistrationFailed = false

    init() {
        launchAtLogin = Preferences.launchAtLogin
        showFreeSpaceInMenuBar = Preferences.showFreeSpaceInMenuBar
        dockerIntegrationEnabled = Preferences.dockerEnabled
        menuBarMetric = Preferences.menuBarMetric
        commandBarEnabled = Preferences.commandBarEnabled
        commandBarHotKey = Preferences.commandBarHotKey
        policy = Preferences.policy
        collapsedSections = Preferences.collapsedSections
        volume = diskService.volumeSnapshot()
        power = PowerService.shared.read()
    }

    // MARK: - Lifecycle

    /// Called once at launch for the things that must work whether or not the panel
    /// has ever been opened — the global shortcut, and the menu-bar figure.
    func applicationDidLaunch(openReview: @escaping () -> Void) {
        guard !hasLaunched else { return }
        hasLaunched = true
        openReviewWindow = openReview
        CommandBarController.shared.configure { [weak self] entry in
            self?.execute(entry)
        }
        registerCommandBarHotKey()
        startRefreshLoopIfNeeded()
        // The menu bar can show a live metric, which needs sampling even when the
        // panel is closed. When it shows free space, it doesn't.
        if menuBarMetric == .cpu || menuBarMetric == .memory {
            startMetricsLoop()
        }
    }

    /// Opening the panel refreshes only the volume figure — a resource-value read
    /// that opens no directories. Nothing walks the disk until the user asks.
    func panelDidAppear() {
        volume = diskService.volumeSnapshot()
        power = PowerService.shared.read()
        startRefreshLoopIfNeeded()
        startMetricsLoop()
        if dockerIntegrationEnabled, dockerStats.isDockerAvailable == false, !isLoadingDocker {
            Task { await refreshDocker() }
        }
    }

    /// Sampling once a second is only worth doing while someone is looking. When
    /// the panel closes the loop stops unless the menu bar itself needs a metric —
    /// otherwise a closed panel would keep waking the CPU forever.
    func panelDidDisappear() {
        guard menuBarMetric != .cpu, menuBarMetric != .memory else { return }
        metricsTask?.cancel()
        metricsTask = nil
        SystemMetricsService.shared.resetRates()
    }

    private func startMetricsLoop() {
        guard metricsTask == nil else { return }
        SystemMetricsService.shared.resetRates()
        metricsTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let sample = SystemMetricsService.shared.sample()
                self.metrics = sample
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func registerCommandBarHotKey() {
        guard commandBarEnabled else {
            HotKeyService.shared.unregister(name: "commandBar")
            hotKeyRegistrationFailed = false
            return
        }
        let registered = HotKeyService.shared.register(commandBarHotKey, name: "commandBar") {
            CommandBarController.shared.toggle()
        }
        hotKeyRegistrationFailed = !registered
    }

    // MARK: - Tools

    func pickColor() async {
        if let text = await colorPicker.pick() {
            lastPickedColor = text
            statusMessage = "Copied \(text)"
        }
    }

    func showCommandBar() {
        CommandBarController.shared.show()
    }

    /// Runs whatever the command bar selected. Apps launch, actions route back into
    /// the app, and anything textual lands on the clipboard.
    func execute(_ entry: CommandEntry) {
        switch entry.kind {
        case .app:
            guard let path = entry.iconPath else { return }
            NSWorkspace.shared.openApplication(
                at: URL(fileURLWithPath: path),
                configuration: NSWorkspace.OpenConfiguration()
            )

        case .math:
            colorPicker.copy(entry.title)
            statusMessage = "Copied \(entry.title)"

        case .clipboard:
            let id = entry.id.replacingOccurrences(of: "clip:", with: "")
            if let match = clipboard.entries.first(where: { $0.id.uuidString == id }) {
                clipboard.copyToPasteboard(match)
                statusMessage = "Copied from clipboard history"
            }

        case .color:
            Task { await pickColor() }

        case .action:
            runAction(entry.id)
        }
    }

    private func runAction(_ id: String) {
        switch id {
        case "action:scan":
            Task { await runScan() }
        case "action:review":
            NSApp.activate(ignoringOtherApps: true)
            openReviewWindow?()
        case "action:keepawake":
            keepAwake.toggle()
            statusMessage = keepAwake.isActive ? "Keep Awake on" : "Keep Awake off"
        case "action:color":
            Task { await pickColor() }
        case "action:clipboard":
            collapsedSections.remove(.clipboard)
            Preferences.collapsedSections = collapsedSections
            statusMessage = "Clipboard history is in the panel"
        case "action:emptytrash":
            NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appending(path: ".Trash"))
        default:
            break
        }
    }

    /// Set by the app scene, which is the only place that owns `openWindow`.
    private var openReviewWindow: (() -> Void)?
    private var hasLaunched = false

    private func startRefreshLoopIfNeeded() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard let self, !Task.isCancelled else { return }
                self.volume = self.diskService.volumeSnapshot()
                self.power = PowerService.shared.read()
            }
        }
    }

    // MARK: - Cleaner actions

    func runScan() async {
        guard !isScanning else { return }
        isScanning = true
        lastReport = nil
        scanProgress = CleanerProgress(category: nil, detail: "Starting", fraction: 0)

        let policy = policy
        let result = await cleanerService.scan(policy: policy) { [weak self] progress in
            Task { @MainActor in self?.scanProgress = progress }
        }

        scan = result
        selectedItemIDs = Set(result.items.filter { policy.preselects($0) }.map(\.id))
        expandedCategories = []
        isScanning = false
        volume = diskService.volumeSnapshot()

        statusMessage = result.isEmpty
            ? "Nothing to clean — your Mac is tidy."
            : "Found \(ByteFormat.string(result.totalBytes)) in \(result.items.count) items."
    }

    func removeSelected() async {
        guard let scan, !isRemoving else { return }
        let targets = scan.items.filter { selectedItemIDs.contains($0.id) }
        guard !targets.isEmpty else { return }

        isRemoving = true
        let report = await cleanerService.remove(targets)
        isRemoving = false

        lastReport = report
        statusMessage = report.summary
        if let failure = report.failures.first, report.failures.count == report.itemsRemoved + report.failures.count {
            errorMessage = failure.reason
        }

        // Drop what's gone rather than forcing a full rescan; the remaining rows are
        // still accurate and the user keeps their place in the list.
        let removedIDs = Set(targets.map(\.id))
        self.scan?.items.removeAll { removedIDs.contains($0.id) }
        selectedItemIDs.subtract(removedIDs)
        volume = diskService.volumeSnapshot()
    }

    func isSelected(_ item: CleanableItem) -> Bool {
        selectedItemIDs.contains(item.id)
    }

    func toggle(_ item: CleanableItem) {
        if selectedItemIDs.contains(item.id) {
            selectedItemIDs.remove(item.id)
        } else {
            selectedItemIDs.insert(item.id)
        }
    }

    func selectionState(for category: CleanerCategory) -> SelectionState {
        guard let scan else { return .none }
        let items = scan.items(in: category)
        guard !items.isEmpty else { return .none }
        let selected = items.filter { selectedItemIDs.contains($0.id) }.count
        if selected == 0 { return .none }
        return selected == items.count ? .all : .partial
    }

    func toggleCategory(_ category: CleanerCategory) {
        guard let scan else { return }
        let ids = scan.items(in: category).map(\.id)
        if selectionState(for: category) == .all {
            selectedItemIDs.subtract(ids)
        } else {
            selectedItemIDs.formUnion(ids)
        }
    }

    func toggleExpanded(_ category: CleanerCategory) {
        if expandedCategories.contains(category) {
            expandedCategories.remove(category)
        } else {
            expandedCategories.insert(category)
        }
    }

    func selectedBytes(in category: CleanerCategory) -> UInt64 {
        guard let scan else { return 0 }
        return scan.items(in: category)
            .filter { selectedItemIDs.contains($0.id) }
            .reduce(0) { $0 + $1.size }
    }

    func revealInFinder(_ item: CleanableItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    // MARK: - Large folders

    func loadLargeFolders() async {
        guard !isLoadingLargeFolders else { return }
        isLoadingLargeFolders = true
        defer { isLoadingLargeFolders = false }

        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots = ["Downloads", "Documents", "Desktop", "Movies", "Music", "Pictures",
                     "Library/Containers", "Library/Application Support", "Library/Caches",
                     "Library/Developer", "Library/Group Containers"]

        let sized = await mapConcurrently(roots, maxConcurrent: 4) { relative -> LargeFolder? in
            let url = home.appending(path: relative)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let size = DiskService.shared.allocatedSize(at: url)
            guard size > 0 else { return nil }
            return LargeFolder(path: url.path, name: relative, size: size)
        }

        largeFolders = sized.compactMap { $0 }.sorted { $0.size > $1.size }
    }

    func revealFolder(_ folder: LargeFolder) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: folder.path)])
    }

    // MARK: - Docker

    func refreshDocker() async {
        guard dockerIntegrationEnabled, !isLoadingDocker else { return }
        isLoadingDocker = true
        defer { isLoadingDocker = false }
        dockerStats = await dockerService.fetchStats()
    }

    func pruneDocker() async {
        guard ProcessRunner.commandExists("docker") else {
            errorMessage = "Docker CLI not found."
            return
        }
        isLoadingDocker = true
        let before = dockerStats.reclaimableSize
        _ = try? ProcessRunner.runShell("docker system prune -f")
        isLoadingDocker = false
        dockerStats = await dockerService.fetchStats()
        statusMessage = before > 0 ? "Docker pruned — \(ByteFormat.string(before)) reclaimable cleared" : "Docker pruned"
    }

    // MARK: - Panel chrome

    func isCollapsed(_ section: PanelSection) -> Bool {
        collapsedSections.contains(section)
    }

    func toggleCollapsed(_ section: PanelSection) {
        if collapsedSections.contains(section) {
            collapsedSections.remove(section)
        } else {
            collapsedSections.insert(section)
        }
        Preferences.collapsedSections = collapsedSections
    }

    func persistPolicy() {
        Preferences.policy = policy
    }

    func dismissError() {
        errorMessage = nil
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }
}

enum SelectionState {
    case none, partial, all

    var symbolName: String {
        switch self {
        case .none: "square"
        case .partial: "minus.square.fill"
        case .all: "checkmark.square.fill"
        }
    }
}
