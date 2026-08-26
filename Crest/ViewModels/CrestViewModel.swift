//
//  CrestViewModel.swift
//  Crest
//

import AppKit
import Foundation
import Observation
import SwiftUI

/// The sections stacked in the menu-bar panel, in display order.
nonisolated enum PanelSection: String, CaseIterable, Identifiable, Codable {
    case system = "System"
    case disk = "Disk"
    case cleaner = "Cleaner"
    case network = "Network"
    case power = "Power"
    case tools = "Tools"
    case clipboard = "Clipboard"
    case largeFolders = "Large folders"
    case docker = "Docker"
    case homebrew = "Homebrew"
    case voice = "Voice"
    case meetings = "Meetings"

    var id: String { rawValue }

    /// One line saying what the tab is for, shown where the user is choosing
    /// whether to keep it.
    var blurb: String {
        switch self {
        case .system: "CPU, memory and uptime"
        case .disk: "Free space and what fills it"
        case .cleaner: "Find and remove reclaimable files"
        case .network: "Live speed and which apps use it"
        case .power: "Battery health and charge"
        case .tools: "Keep Awake, colour picker, uninstaller"
        case .clipboard: "Recent copies, searchable"
        case .largeFolders: "The biggest folders in your home"
        case .docker: "Images, containers and build cache"
        case .homebrew: "Outdated packages and brew cleanup"
        case .voice: "Hold a key, talk, and the text lands where you're typing"
        case .meetings: "Record a call and get an on-device summary"
        }
    }

    var iconName: String {
        switch self {
        case .system: "gauge.with.dots.needle.67percent"
        case .disk: "internaldrive"
        case .cleaner: "sparkles"
        case .network: "network"
        case .power: "bolt"
        case .tools: "wrench.and.screwdriver"
        case .clipboard: "doc.on.clipboard"
        case .largeFolders: "chart.bar"
        case .docker: "shippingbox"
        case .homebrew: "cup.and.saucer"
        case .voice: "mic"
        case .meetings: "text.bubble"
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
final class CrestViewModel {

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
    let network = NetworkService.shared
    let homebrew = HomebrewService.shared
    let commandBar = CommandBarService.shared

    private var metricsTask: Task<Void, Never>?

    // MARK: - Other sections

    var largeFolders: [LargeFolder] = []
    var isLoadingLargeFolders = false

    var dockerStats = DockerStats()
    var isLoadingDocker = false

    // MARK: - Uninstaller

    var uninstallScan: UninstallScan?
    var uninstallSelection: Set<String> = []
    var isScanningApp = false
    var isUninstalling = false
    var uninstallReport: UninstallReport?

    var uninstallSelectionCount: Int { uninstallSelection.count }

    var uninstallSelectedBytes: UInt64 {
        guard let uninstallScan else { return 0 }
        return uninstallScan.items
            .filter { uninstallSelection.contains($0.id) }
            .reduce(0) { $0 + $1.size }
    }

    var uninstallTargetName: String { uninstallScan?.target.name ?? "The app" }

    // MARK: - Chrome

    /// Which tab is showing. One section at a time replaces the old stack of
    /// eight collapsible cards: the panel stays one screen tall regardless of how
    /// much each section has to say, and only the visible section builds any views.
    var selectedSection: PanelSection = .system {
        didSet {
            guard selectedSection != oldValue else { return }
            Preferences.selectedSection = selectedSection
            syncMetricsLoop()
        }
    }

    /// The tabs actually on screen: the ones the user kept, in the order they put
    /// them in. Docker and Homebrew carry the extra condition that their
    /// integration is on, so a tab never leads to a disabled feature.
    var visibleSections: [PanelSection] {
        sectionOrder.filter { section in
            guard enabledSections.contains(section) else { return false }
            switch section {
            case .docker: return dockerIntegrationEnabled
            case .homebrew: return homebrewEnabled
            default: return true
            }
        }
    }

    /// Which sections the user kept.
    private(set) var enabledSections: Set<PanelSection> = Set(PanelSection.allCases)
    /// The order they appear in the tab bar.
    private(set) var sectionOrder: [PanelSection] = PanelSection.allCases

    /// Turns a section on or off, keeping the two integration flags that predate
    /// this list in step so the rest of the app keeps reading one answer.
    func setSection(_ section: PanelSection, enabled: Bool) {
        // The panel would have nothing to show with every tab off, and the tab bar
        // no way back — so the last one standing cannot be turned off.
        if !enabled, enabledSections.count <= 1, enabledSections.contains(section) { return }

        if enabled { enabledSections.insert(section) } else { enabledSections.remove(section) }
        Preferences.enabledSections = enabledSections

        switch section {
        case .docker: dockerIntegrationEnabled = enabled
        case .homebrew: homebrewEnabled = enabled
        default: break
        }
        // Leaving the selection on a tab that no longer exists would strand the
        // panel showing nothing at all.
        if !enabled, selectedSection == section {
            selectedSection = visibleSections.first ?? .system
        }
    }

    /// Moves a section one place up or down the tab bar.
    func moveSection(_ section: PanelSection, by delta: Int) {
        guard let index = sectionOrder.firstIndex(of: section) else { return }
        let target = index + delta
        guard sectionOrder.indices.contains(target) else { return }
        sectionOrder.swapAt(index, target)
        Preferences.sectionOrder = sectionOrder
    }

    /// Back to every section, in the order the app ships them.
    func resetSections() {
        enabledSections = Set(PanelSection.allCases)
        sectionOrder = PanelSection.allCases
        Preferences.enabledSections = enabledSections
        Preferences.sectionOrder = sectionOrder
        dockerIntegrationEnabled = true
        homebrewEnabled = true
    }
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
    var homebrewEnabled: Bool {
        didSet {
            Preferences.homebrewEnabled = homebrewEnabled
            // Leaving the tab while it is selected would strand the panel on a
            // section that no longer exists, showing nothing at all.
            if !homebrewEnabled, selectedSection == .homebrew { selectedSection = .system }
        }
    }
    var menuBarIcon: MenuBarIcon { didSet { Preferences.menuBarIcon = menuBarIcon } }
    var menuBarMetric: MenuBarMetric {
        didSet {
            Preferences.menuBarMetric = menuBarMetric
            syncMetricsLoop()
        }
    }
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

    var automaticUpdateChecks: Bool { didSet { Preferences.automaticUpdateChecks = automaticUpdateChecks } }
    var fileSearchEnabled: Bool { didSet { Preferences.fileSearchEnabled = fileSearchEnabled } }
    var filePreviewEnabled: Bool { didSet { Preferences.filePreviewEnabled = filePreviewEnabled } }

    let userHotKeys = UserHotKeyService.shared
    let updates = UpdateService.shared

    // MARK: - Voice

    let dictation = DictationService()
    let meetings = MeetingRecorder()
    let voiceHistory = DictationHistory.shared
    let meetingStore = MeetingStore.shared
    let vocabulary = VocabularyStore.shared

    var voiceEnabled: Bool {
        didSet {
            Preferences.voiceEnabled = voiceEnabled
            dictation.reload()
            if voiceEnabled {
                // Asked here rather than at the first utterance. Switching the feature
                // on is the moment the user is looking at the screen and expecting to be
                // asked; a prompt that arrives mid-hold takes focus, interrupts the
                // recording, and covers the app the text was meant for.
                Task { await dictation.requestPermissions() }
            } else {
                VoiceHUDController.shared.teardown()
            }
        }
    }
    var pushToTalkKey: PushToTalkKey {
        didSet {
            Preferences.pushToTalkKey = pushToTalkKey
            dictation.reload()
        }
    }
    var voiceHandsFree: Bool { didSet { Preferences.voiceHandsFreeEnabled = voiceHandsFree } }
    var voiceSound: Bool { didSet { Preferences.voiceSoundEnabled = voiceSound } }
    var voiceLearnAppNames: Bool {
        didSet {
            Preferences.voiceLearnAppNames = voiceLearnAppNames
            voiceLearnAppNames ? learnAppNames() : vocabulary.learn(appNames: [])
        }
    }
    var dictationCleanup: CleanupMode { didSet { Preferences.dictationCleanup = dictationCleanup } }
    var typingWordsPerMinute: Int { didSet { Preferences.typingWordsPerMinute = typingWordsPerMinute } }
    /// nil means "pick a style from whichever app is frontmost".
    var dictationStyle: DictationStyle? { didSet { Preferences.dictationStyle = dictationStyle } }
    var commandModeEnabled: Bool {
        didSet {
            Preferences.commandModeEnabled = commandModeEnabled
            dictation.reload()
        }
    }
    var commandModeKey: PushToTalkKey {
        didSet {
            Preferences.commandModeKey = commandModeKey
            dictation.reload()
        }
    }

    var meetingsEnabled: Bool {
        didSet {
            Preferences.meetingsEnabled = meetingsEnabled
            meetingsEnabled ? meetings.startDetecting() : meetings.stopDetecting()
            if meetingsEnabled {
                // Same reasoning as dictation, and more so: a prompt landing part way
                // into a call is the worst possible time to interrupt someone.
                Task { await dictation.requestMicrophoneAccess() }
            } else {
                MeetingHUDController.shared.teardown()
            }
        }
    }
    var meetingCaptureMicrophone: Bool { didSet { Preferences.meetingCaptureMicrophone = meetingCaptureMicrophone } }
    var meetingCaptureSystemAudio: Bool { didSet { Preferences.meetingCaptureSystemAudio = meetingCaptureSystemAudio } }
    var meetingAutoSummarize: Bool { didSet { Preferences.meetingAutoSummarize = meetingAutoSummarize } }
    var meetingSuggestOnCall: Bool {
        didSet {
            Preferences.meetingSuggestOnCall = meetingSuggestOnCall
            meetingSuggestOnCall ? meetings.startDetecting() : meetings.stopDetecting()
        }
    }

    init() {
        launchAtLogin = Preferences.launchAtLogin
        showFreeSpaceInMenuBar = Preferences.showFreeSpaceInMenuBar
        dockerIntegrationEnabled = Preferences.dockerEnabled
        homebrewEnabled = Preferences.homebrewEnabled
        menuBarMetric = Preferences.menuBarMetric
        menuBarIcon = Preferences.menuBarIcon
        commandBarEnabled = Preferences.commandBarEnabled
        commandBarHotKey = Preferences.commandBarHotKey
        automaticUpdateChecks = Preferences.automaticUpdateChecks
        fileSearchEnabled = Preferences.fileSearchEnabled
        filePreviewEnabled = Preferences.filePreviewEnabled
        voiceEnabled = Preferences.voiceEnabled
        pushToTalkKey = Preferences.pushToTalkKey
        voiceHandsFree = Preferences.voiceHandsFreeEnabled
        voiceSound = Preferences.voiceSoundEnabled
        voiceLearnAppNames = Preferences.voiceLearnAppNames
        dictationCleanup = Preferences.dictationCleanup
        typingWordsPerMinute = Preferences.typingWordsPerMinute
        dictationStyle = Preferences.dictationStyle
        commandModeEnabled = Preferences.commandModeEnabled
        commandModeKey = Preferences.commandModeKey
        meetingsEnabled = Preferences.meetingsEnabled
        meetingCaptureMicrophone = Preferences.meetingCaptureMicrophone
        meetingCaptureSystemAudio = Preferences.meetingCaptureSystemAudio
        meetingAutoSummarize = Preferences.meetingAutoSummarize
        meetingSuggestOnCall = Preferences.meetingSuggestOnCall
        policy = Preferences.policy
        selectedSection = Preferences.selectedSection

        // The two integration flags predate the section list and are still what
        // the Docker and Homebrew code paths read, so a stored "off" wins here
        // rather than being silently switched back on by the newer setting.
        var sections = Preferences.enabledSections ?? Set(PanelSection.allCases)
        // Sections introduced after this user last touched the list. Without this a
        // stored set from an older release would hide every new tab forever, and the
        // only way to find one would be to already know it existed.
        let seen = Preferences.storedSectionOrder
        if !seen.isEmpty {
            sections.formUnion(PanelSection.allCases.filter { !seen.contains($0) })
        }
        if !dockerIntegrationEnabled { sections.remove(.docker) }
        if !homebrewEnabled { sections.remove(.homebrew) }
        if sections.isEmpty { sections = [.system] }
        enabledSections = sections
        sectionOrder = Preferences.sectionOrder
        volume = diskService.volumeSnapshot()
        power = PowerService.shared.read()
    }

    // MARK: - Lifecycle

    /// Called once at launch for the things that must work whether or not the panel
    /// has ever been opened — the global shortcut, and the menu-bar figure.
    func applicationDidLaunch(
        openReview: @escaping () -> Void,
        openUninstaller: @escaping () -> Void,
        openSettings: @escaping () -> Void,
        openMeetings: @escaping () -> Void
    ) {
        guard !hasLaunched else { return }
        hasLaunched = true
        openReviewWindow = openReview
        openUninstallerWindow = openUninstaller
        openSettingsWindow = openSettings
        openMeetingsWindow = openMeetings
        CommandBarController.shared.configure { [weak self] entry in
            self?.execute(entry)
        }
        registerCommandBarHotKey()
        UserHotKeyService.shared.performAction = { [weak self] id in
            self?.runAction(id)
        }
        UserHotKeyService.shared.registerAll()
        // Indexing apps at launch, off the main actor, so the first press of the
        // shortcut searches a populated list instead of an empty one.
        CommandBarService.shared.buildIndex()
        configureVoice()

        // First run, or a release that added steps worth showing. Everything in it
        // is skippable, so it never stands between the user and the app.
        if OnboardingController.isPending {
            OnboardingController.shared.show(viewModel: self)
        }
        updates.checkInBackgroundIfDue()
        startRefreshLoopIfNeeded()
        // The menu bar can show a live metric, which needs sampling even when the
        // panel is closed. When it shows free space, it doesn't.
        syncMetricsLoop()
    }

    /// Opening the panel refreshes only the volume figure — a resource-value read
    /// that opens no directories. Nothing walks the disk until the user asks.
    func panelDidAppear() {
        isPanelOpen = true
        // A section turned off in Settings while the panel was closed would
        // otherwise leave the panel showing a tab that no longer has a tab.
        if !visibleSections.contains(selectedSection) {
            selectedSection = visibleSections.first ?? .system
        }
        volume = diskService.volumeSnapshot()
        power = PowerService.shared.read()
        startRefreshLoopIfNeeded()
        syncMetricsLoop()
        if dockerIntegrationEnabled, dockerStats.isDockerAvailable == false, !isLoadingDocker {
            Task { await refreshDocker() }
        }
    }

    func panelDidDisappear() {
        isPanelOpen = false
        syncMetricsLoop()
    }

    /// Sampling once a second is only worth doing when something displays the
    /// result: the System tab while the panel is open, or a menu-bar item set to
    /// show CPU or memory. With tabs, sitting on any other tab now costs nothing —
    /// under the old stacked layout the System card was always on screen.
    private var needsMetricsSampling: Bool {
        if menuBarMetric == .cpu || menuBarMetric == .memory { return true }
        return isPanelOpen && selectedSection == .system
    }

    private func syncMetricsLoop() {
        needsMetricsSampling ? startMetricsLoop() : stopMetricsLoop()
    }

    private func startMetricsLoop() {
        guard metricsTask == nil else { return }
        SystemMetricsService.shared.resetRates()
        metricsTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.metrics = SystemMetricsService.shared.sample()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func stopMetricsLoop() {
        guard metricsTask != nil else { return }
        metricsTask?.cancel()
        metricsTask = nil
        SystemMetricsService.shared.resetRates()
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

    // MARK: - Voice

    /// Arms dictation, the call detector and the two floating panels.
    ///
    /// The panels are driven by callbacks rather than by observing the services from a
    /// view: ordering an `NSPanel` in and out is a side effect, and there is no view on
    /// screen to host that observation while the panel is the thing being shown.
    private func configureVoice() {
        dictation.onPhaseChange = { [weak self] in
            guard let self else { return }
            VoiceHUDController.shared.update(service: self.dictation)
        }
        meetings.onStateChange = { [weak self] in
            guard let self else { return }
            MeetingHUDController.shared.update(recorder: self.meetings)
        }

        dictation.reload()
        if meetingsEnabled { meetings.startDetecting() }

        // App names make the best vocabulary entries available for free: the index is
        // already built for the command bar, and a product name the recognizer has never
        // heard is exactly what biasing is for. Deferred so it never delays launch.
        if voiceLearnAppNames {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                self.learnAppNames()
            }
        }
    }

    private func learnAppNames() {
        vocabulary.learn(appNames: CommandBarService.shared.apps.map(\.title))
    }

    /// Starts or stops a recording from a button, for anyone who would rather not hold a
    /// key down.
    func toggleDictation() {
        guard voiceEnabled else {
            statusMessage = "Turn on Voice in Settings first"
            openSettings()
            return
        }
        dictation.toggleFromButton()
    }

    func startMeeting() {
        guard meetingsEnabled else {
            statusMessage = "Turn on Meeting notes in Settings first"
            openSettings()
            return
        }
        meetings.start()
    }

    func stopMeeting() {
        meetings.stop()
    }

    func openMeetings() {
        NSApp.activate(ignoringOtherApps: true)
        openMeetingsWindow?()
    }

    /// Copies the most recent dictation, for when it landed somewhere it should not have.
    func copyLastDictation() {
        guard let last = voiceHistory.entries.first else {
            statusMessage = "No dictations yet"
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(last.text, forType: .string)
        statusMessage = "Copied your last dictation"
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

    /// Runs whatever the command bar selected.
    ///
    /// The action itself says what to do, so most results need nothing here: apps,
    /// files, settings panes and system commands all go straight to the runner.
    /// Only Crest's own tools come back into the view model, because those are
    /// the only ones that touch app state.
    func execute(_ entry: CommandEntry) {
        CommandBarService.shared.recordUse(entry)

        if case .appAction(let id) = entry.action {
            runAction(id)
            return
        }
        if let message = CommandRunner.run(entry.action) {
            statusMessage = message
        }
    }

    private func runAction(_ id: String) {
        // Panel sections share one prefix, so a new section needs no case here.
        if id.hasPrefix("section:") {
            let raw = String(id.dropFirst("section:".count))
            guard let section = PanelSection(rawValue: raw) else { return }
            selectedSection = section
            statusMessage = "\(section.rawValue) is open in the panel"
            return
        }

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
            selectedSection = .clipboard
            statusMessage = "Clipboard history is in the panel"
        case "action:uninstall":
            openUninstaller()
        case "action:network":
            selectedSection = .network
        case "action:brewupdate":
            guard homebrewEnabled else { break }
            selectedSection = .homebrew
            Task { await homebrew.upgradeAll() }
        case "action:brewcleanup":
            guard homebrewEnabled else { break }
            selectedSection = .homebrew
            Task { await homebrew.cleanup() }
        case "action:reindex":
            commandBar.buildIndex(force: true)
            statusMessage = "Rebuilding the search index"
        case "action:settings":
            openSettings()
        case "action:shortcuts":
            openSettings()
            statusMessage = "Shortcuts are in Settings"
        case "action:onboarding":
            replayOnboarding()
        case "action:checkupdates":
            updates.check()
            statusMessage = "Checking for updates"
        case "action:dictate":
            toggleDictation()
        case "action:meeting":
            meetings.state.isRecording ? stopMeeting() : startMeeting()
        case "action:meetingnotes":
            openMeetings()
        case "action:lastdictation":
            copyLastDictation()
        case "action:vocabulary":
            openSettings()
            statusMessage = "Your voice vocabulary is in Settings ▸ Voice"
        default:
            break
        }
    }

    /// Set by the app scene, which is the only place that owns `openWindow`.
    private var openReviewWindow: (() -> Void)?
    private var openUninstallerWindow: (() -> Void)?
    private var openSettingsWindow: (() -> Void)?
    private var openMeetingsWindow: (() -> Void)?
    private var hasLaunched = false
    private var isPanelOpen = false

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

    // MARK: - Homebrew

    /// The panel calls this whenever the Homebrew tab appears. A plain refresh is
    /// skipped when the list is already loaded, because `brew info` on every
    /// installed package is a subprocess and the answer does not change between
    /// two glances at the same panel.
    func refreshHomebrew(force: Bool = false) async {
        guard homebrewEnabled else { return }
        if !force, homebrew.availability.isReady, !homebrew.installed.isEmpty { return }
        await homebrew.refresh()
    }

    // MARK: - Uninstaller

    func openUninstaller() {
        NSApp.activate(ignoringOtherApps: true)
        openUninstallerWindow?()
    }

    /// Opens the uninstaller on a specific app, so the command bar and a Finder
    /// drag land in the same place as picking one from the list.
    func openUninstaller(for url: URL) {
        openUninstaller()
        Task { await chooseAppToUninstall(at: url) }
    }

    func chooseAppToUninstall(at url: URL) async {
        guard !isScanningApp, let target = UninstallerService.shared.target(for: url) else { return }
        isScanningApp = true
        uninstallReport = nil
        uninstallScan = nil

        let result = await UninstallerService.shared.scan(target)
        uninstallScan = result
        // The app bundle and its own support files start ticked; anything the
        // scanner is less sure about starts clear, so a hasty click cannot remove
        // something the user has not looked at.
        uninstallSelection = Set(result.items.filter { $0.category.selectedByDefault }.map(\.id))
        isScanningApp = false
    }

    func isLeftoverSelected(_ item: LeftoverItem) -> Bool {
        uninstallSelection.contains(item.id)
    }

    func toggleLeftover(_ item: LeftoverItem) {
        if uninstallSelection.contains(item.id) {
            uninstallSelection.remove(item.id)
        } else {
            uninstallSelection.insert(item.id)
        }
    }

    func leftoverSelectionState(for category: LeftoverCategory) -> SelectionState {
        guard let uninstallScan else { return .none }
        let items = uninstallScan.items(in: category)
        guard !items.isEmpty else { return .none }
        let selected = items.filter { uninstallSelection.contains($0.id) }.count
        if selected == 0 { return .none }
        return selected == items.count ? .all : .partial
    }

    func toggleLeftoverCategory(_ category: LeftoverCategory) {
        guard let uninstallScan else { return }
        let ids = uninstallScan.items(in: category).map(\.id)
        if leftoverSelectionState(for: category) == .all {
            uninstallSelection.subtract(ids)
        } else {
            uninstallSelection.formUnion(ids)
        }
    }

    func performUninstall() async {
        guard let uninstallScan, !isUninstalling else { return }
        let targets = uninstallScan.items.filter { uninstallSelection.contains($0.id) }
        guard !targets.isEmpty else { return }

        isUninstalling = true
        // Quitting first matters more than it looks: an app still running rewrites
        // its preferences as it exits, putting back the file just removed.
        await UninstallerService.shared.quitIfRunning(uninstallScan.target)
        let report = await UninstallerService.shared.remove(targets)
        isUninstalling = false

        uninstallReport = report
        statusMessage = report.summary
        volume = diskService.volumeSnapshot()
        // The command bar's app list still holds the app that was just removed.
        commandBar.buildIndex(force: true)
    }

    func resetUninstaller() {
        uninstallScan = nil
        uninstallSelection = []
        uninstallReport = nil
    }

    // MARK: - Panel chrome

    func select(_ section: PanelSection) {
        selectedSection = section
    }

    func persistPolicy() {
        Preferences.policy = policy
    }

    func dismissError() {
        errorMessage = nil
    }

    /// Opens Crest's own Settings window.
    ///
    /// The window is a scene with an id rather than SwiftUI's `Settings`, because
    /// that one can only be opened by a `SettingsLink` view — which is no use to a
    /// command-bar action or a global shortcut.
    func openSettings() {
        // Plain activation, not `AppActivation`: an accessory app can show and
        // focus an ordinary window, and raising the policy here would leave a Dock
        // icon behind for the rest of the session — nothing lowers it when a
        // window scene closes.
        NSApp.activate(ignoringOtherApps: true)
        openSettingsWindow?()
    }

    /// Shows the first-run flow again, from Settings › About.
    func replayOnboarding() {
        Preferences.completedOnboardingVersion = 0
        OnboardingController.shared.show(viewModel: self)
    }

    /// Opens the Full Disk Access list. The pane cannot be scrolled to a specific
    /// app from outside, so this lands the user on the right list and no further —
    /// which is still several clicks better than describing where to find it.
    func openFullDiskAccessSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        ) else { return }
        NSWorkspace.shared.open(url)
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
