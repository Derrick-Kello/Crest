//
//  AppSettings.swift
//  Crest
//

import Foundation
import OSLog
import ServiceManagement

/// Thin, typed wrapper over `UserDefaults`. Every property reads and writes on
/// access — there is no in-memory mirror to fall out of sync with what's on disk.
enum Preferences {
    private static let defaults = UserDefaults.standard
    private static let logger = Logger(subsystem: "com.smarthive.crest", category: "Settings")

    private enum Key {
        static let showFreeSpace = "showFreeSpaceInMenuBar"
        static let dockerEnabled = "dockerEnabled"
        static let homebrewEnabled = "homebrewEnabled"
        static let policy = "cleanerPolicy"
        static let selectedSection = "selectedPanelSection"
        static let clipboardEnabled = "clipboardEnabled"
        static let colorFormat = "colorFormat"
        static let colorBareHex = "colorBareHex"
        static let recentColors = "recentColors"
        static let commandBarEnabled = "commandBarEnabled"
        static let commandBarHotKey = "commandBarHotKey"
        static let menuBarMetric = "menuBarMetric"
        static let menuBarIcon = "menuBarIcon"
        static let launchHistory = "commandBarLaunchHistory"
        static let userHotKeys = "userHotKeys"
        static let commandAliases = "commandAliases"
        static let enabledSections = "enabledPanelSections"
        static let sectionOrder = "panelSectionOrder"
        static let onboardingVersion = "completedOnboardingVersion"
        static let lastUpdateCheck = "lastUpdateCheck"
        static let automaticUpdateChecks = "automaticUpdateChecks"
        static let fileSearchEnabled = "fileSearchEnabled"
        static let filePreviewEnabled = "filePreviewEnabled"
        static let voiceEnabled = "voiceEnabled"
        static let pushToTalkKey = "voicePushToTalkKey"
        static let voiceHandsFree = "voiceHandsFree"
        static let voiceSound = "voiceSound"
        static let voiceLearnAppNames = "voiceLearnAppNames"
        static let typingWordsPerMinute = "typingWordsPerMinute"
        static let dictationCleanup = "voiceCleanupMode"
        static let dictationStyle = "voiceDictationStyle"
        static let dictationStyleOverrides = "voiceDictationStyleOverrides"
        static let commandModeEnabled = "voiceCommandModeEnabled"
        static let commandModeKey = "voiceCommandModeKey"
        static let meetingsEnabled = "meetingsEnabled"
        static let meetingCaptureMicrophone = "meetingCaptureMicrophone"
        static let meetingCaptureSystem = "meetingCaptureSystemAudio"
        static let meetingAutoSummarize = "meetingAutoSummarize"
        static let meetingSuggestOnCall = "meetingSuggestOnCall"
        static let meetingKeepAudio = "meetingKeepAudio"
        static let tilingEnabled = "tilingEnabled"
        static let tilingInnerGap = "tilingInnerGap"
        static let tilingOuterGap = "tilingOuterGap"
        static let tilingExcluded = "tilingExcludedBundleIDs"
        static let tilingLayouts = "tilingWorkspaceLayouts"
        static let tilingKeyOverrides = "tilingKeyOverrides"
        static let tilingModifier = "tilingModifier"
    }

    // MARK: - Voice

    /// Master switch for dictation. Off by default: it needs Accessibility, and an app
    /// that silently asks for a system-wide event tap on first launch has not earned it.
    static var voiceEnabled: Bool {
        get { defaults.bool(forKey: Key.voiceEnabled) }
        set { defaults.set(newValue, forKey: Key.voiceEnabled) }
    }

    /// The modifier held to dictate. Right ⌥ by default — it is on every Mac keyboard,
    /// almost nothing binds it, and it is reachable without moving your hand off home.
    static var pushToTalkKey: PushToTalkKey {
        get { PushToTalkKey(rawValue: defaults.string(forKey: Key.pushToTalkKey) ?? "") ?? .rightOption }
        set { defaults.set(newValue.rawValue, forKey: Key.pushToTalkKey) }
    }

    /// Whether a quick tap locks the microphone open instead of stopping.
    static var voiceHandsFreeEnabled: Bool {
        get { defaults.object(forKey: Key.voiceHandsFree) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.voiceHandsFree) }
    }

    static var voiceSoundEnabled: Bool {
        get { defaults.object(forKey: Key.voiceSound) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.voiceSound) }
    }

    /// Whether app names from the command bar's index are fed to the recognizer as
    /// vocabulary. Costs nothing and fixes the most common class of mishearing.
    static var voiceLearnAppNames: Bool {
        get { defaults.object(forKey: Key.voiceLearnAppNames) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.voiceLearnAppNames) }
    }

    /// How fast the user types, used as the baseline for the time-saved figure.
    ///
    /// A setting rather than a constant because the whole number depends on it and it is
    /// the one input Crest cannot measure. 40 is the usual figure quoted for an
    /// average adult on a full keyboard.
    static var typingWordsPerMinute: Int {
        get {
            let stored = defaults.integer(forKey: Key.typingWordsPerMinute)
            return stored > 0 ? stored : 40
        }
        set { defaults.set(newValue, forKey: Key.typingWordsPerMinute) }
    }

    static var dictationCleanup: CleanupMode {
        get { CleanupMode(rawValue: defaults.string(forKey: Key.dictationCleanup) ?? "") ?? .model }
        set { defaults.set(newValue.rawValue, forKey: Key.dictationCleanup) }
    }

    /// A fixed style, or nil to pick one from whichever app is frontmost.
    static var dictationStyle: DictationStyle? {
        get { DictationStyle(rawValue: defaults.string(forKey: Key.dictationStyle) ?? "") }
        set {
            guard let newValue else {
                defaults.removeObject(forKey: Key.dictationStyle)
                return
            }
            defaults.set(newValue.rawValue, forKey: Key.dictationStyle)
        }
    }

    /// Bundle identifier → the style that app always gets, overriding both the automatic
    /// table and the global choice.
    static var dictationStyleOverrides: [String: DictationStyle] {
        get { decode([String: DictationStyle].self, forKey: Key.dictationStyleOverrides) ?? [:] }
        set { encode(newValue, forKey: Key.dictationStyleOverrides) }
    }

    /// Hold a second key with text selected and say what to do with it.
    static var commandModeEnabled: Bool {
        get { defaults.bool(forKey: Key.commandModeEnabled) }
        set { defaults.set(newValue, forKey: Key.commandModeEnabled) }
    }

    static var commandModeKey: PushToTalkKey {
        get { PushToTalkKey(rawValue: defaults.string(forKey: Key.commandModeKey) ?? "") ?? .rightCommand }
        set { defaults.set(newValue.rawValue, forKey: Key.commandModeKey) }
    }

    // MARK: - Meeting notes

    static var meetingsEnabled: Bool {
        get { defaults.bool(forKey: Key.meetingsEnabled) }
        set { defaults.set(newValue, forKey: Key.meetingsEnabled) }
    }

    static var meetingCaptureMicrophone: Bool {
        get { defaults.object(forKey: Key.meetingCaptureMicrophone) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.meetingCaptureMicrophone) }
    }

    static var meetingCaptureSystemAudio: Bool {
        get { defaults.object(forKey: Key.meetingCaptureSystem) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.meetingCaptureSystem) }
    }

    /// Summarize as soon as a meeting stops, rather than waiting to be asked.
    static var meetingAutoSummarize: Bool {
        get { defaults.object(forKey: Key.meetingAutoSummarize) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.meetingAutoSummarize) }
    }

    /// Offer to take notes when a call app starts using the microphone.
    static var meetingSuggestOnCall: Bool {
        get { defaults.object(forKey: Key.meetingSuggestOnCall) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.meetingSuggestOnCall) }
    }

    /// Keep the recorded audio next to the transcript. Off by default: an hour of
    /// meeting audio is far larger than its transcript, and Crest is a disk tool.
    static var meetingKeepAudio: Bool {
        get { defaults.bool(forKey: Key.meetingKeepAudio) }
        set { defaults.set(newValue, forKey: Key.meetingKeepAudio) }
    }

    /// Shortcuts the user assigned to individual apps and Crest actions.
    static var userHotKeys: [UserHotKey] {
        get { decode([UserHotKey].self, forKey: Key.userHotKeys) ?? [] }
        set { encode(newValue, forKey: Key.userHotKeys) }
    }

    /// Catalog item id → the names the user taught the command bar.
    static var commandAliases: [String: [String]] {
        get { decode([String: [String]].self, forKey: Key.commandAliases) ?? [:] }
        set { encode(newValue, forKey: Key.commandAliases) }
    }

    /// Which sections appear in the panel's tab bar.
    ///
    /// Absent rather than empty on a fresh install, so "the user has not chosen"
    /// stays distinguishable from "the user turned everything off" — the first
    /// means show the default set, the second is a state the UI prevents anyway.
    static var enabledSections: Set<PanelSection>? {
        get {
            guard let raw = defaults.array(forKey: Key.enabledSections) as? [String] else { return nil }
            return Set(raw.compactMap(PanelSection.init(rawValue:)))
        }
        set {
            guard let newValue else {
                defaults.removeObject(forKey: Key.enabledSections)
                return
            }
            defaults.set(newValue.map(\.rawValue), forKey: Key.enabledSections)
        }
    }

    /// The order the tabs appear in. Sections added by a later version are absent
    /// from a stored order, so readers append whatever is missing rather than
    /// dropping it.
    static var sectionOrder: [PanelSection] {
        get {
            let stored = storedSectionOrder
            let missing = PanelSection.allCases.filter { !stored.contains($0) }
            return stored + missing
        }
        set { defaults.set(newValue.map(\.rawValue), forKey: Key.sectionOrder) }
    }

    /// Only the sections this user has actually seen. A section absent from here was
    /// added by a later release, which is the difference between "they turned it off"
    /// and "it did not exist yet" — and only the second one should be switched on for
    /// them without asking.
    static var storedSectionOrder: [PanelSection] {
        let raw = defaults.array(forKey: Key.sectionOrder) as? [String] ?? []
        return raw.compactMap(PanelSection.init(rawValue:))
    }

    /// Which onboarding the user has been through. A number rather than a flag so
    /// a future release can show the new steps without replaying the old ones.
    static var completedOnboardingVersion: Int {
        get { defaults.integer(forKey: Key.onboardingVersion) }
        set { defaults.set(newValue, forKey: Key.onboardingVersion) }
    }

    static var lastUpdateCheck: Date? {
        get { defaults.object(forKey: Key.lastUpdateCheck) as? Date }
        set { defaults.set(newValue, forKey: Key.lastUpdateCheck) }
    }

    static var automaticUpdateChecks: Bool {
        get { defaults.object(forKey: Key.automaticUpdateChecks) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.automaticUpdateChecks) }
    }

    /// Whether the command bar folds Spotlight file results into its list.
    static var fileSearchEnabled: Bool {
        get { defaults.object(forKey: Key.fileSearchEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.fileSearchEnabled) }
    }

    /// Whether selecting a file or app shows the preview pane beside the results.
    static var filePreviewEnabled: Bool {
        get { defaults.object(forKey: Key.filePreviewEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.filePreviewEnabled) }
    }

    static var clipboardEnabled: Bool {
        get { defaults.object(forKey: Key.clipboardEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.clipboardEnabled) }
    }

    static var colorFormat: ColorFormat {
        get { ColorFormat(rawValue: defaults.string(forKey: Key.colorFormat) ?? "") ?? .hex }
        set { defaults.set(newValue.rawValue, forKey: Key.colorFormat) }
    }

    static var colorBareHex: Bool {
        get { defaults.bool(forKey: Key.colorBareHex) }
        set { defaults.set(newValue, forKey: Key.colorBareHex) }
    }

    static var recentColors: [PickedColor] {
        get { decode([PickedColor].self, forKey: Key.recentColors) ?? [] }
        set { encode(newValue, forKey: Key.recentColors) }
    }

    static var commandBarEnabled: Bool {
        get { defaults.object(forKey: Key.commandBarEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.commandBarEnabled) }
    }

    static var commandBarHotKey: HotKeyCombo {
        get { decode(HotKeyCombo.self, forKey: Key.commandBarHotKey) ?? .default }
        set { encode(newValue, forKey: Key.commandBarHotKey) }
    }

    /// What the menu-bar item shows next to the icon.
    static var menuBarMetric: MenuBarMetric {
        get { MenuBarMetric(rawValue: defaults.string(forKey: Key.menuBarMetric) ?? "") ?? .freeSpace }
        set { defaults.set(newValue.rawValue, forKey: Key.menuBarMetric) }
    }

    /// The glyph shown in the menu bar.
    static var menuBarIcon: MenuBarIcon {
        get { MenuBarIcon(rawValue: defaults.string(forKey: Key.menuBarIcon) ?? "") ?? .drive }
        set { defaults.set(newValue.rawValue, forKey: Key.menuBarIcon) }
    }

    /// What the command bar has learned about which apps you actually open.
    static var launchHistory: LaunchHistory {
        get { decode(LaunchHistory.self, forKey: Key.launchHistory) ?? LaunchHistory() }
        set { encode(newValue, forKey: Key.launchHistory) }
    }

    // MARK: - Tiling

    /// Master switch for the window manager. Off by default: it needs
    /// Accessibility, and an app that starts rearranging windows the first time it
    /// launches has misread what the user agreed to.
    static var tilingEnabled: Bool {
        get { defaults.bool(forKey: Key.tilingEnabled) }
        set { defaults.set(newValue, forKey: Key.tilingEnabled) }
    }

    /// Space between two windows, in points.
    static var tilingInnerGap: Int {
        get { defaults.object(forKey: Key.tilingInnerGap) as? Int ?? 8 }
        set { defaults.set(min(max(newValue, 0), 64), forKey: Key.tilingInnerGap) }
    }

    /// Space between the windows and the edge of the screen.
    static var tilingOuterGap: Int {
        get { defaults.object(forKey: Key.tilingOuterGap) as? Int ?? 12 }
        set { defaults.set(min(max(newValue, 0), 64), forKey: Key.tilingOuterGap) }
    }

    /// Apps the user has told the tiler to leave alone, on top of the ones it
    /// never touches anyway.
    static var tilingExcludedBundleIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: Key.tilingExcluded) ?? []) }
        set { defaults.set(Array(newValue).sorted(), forKey: Key.tilingExcluded) }
    }

    /// The layout each workspace was last left in. Stored by workspace number
    /// rather than as part of the workspace itself, because a workspace's window
    /// membership is meaningless after a restart and its layout is not.
    static func tilingLayout(forWorkspace index: Int) -> LayoutMode {
        let stored = decode([Int: String].self, forKey: Key.tilingLayouts) ?? [:]
        return stored[index].flatMap(LayoutMode.init(rawValue:)) ?? .dwindle
    }

    static func setTilingLayout(_ mode: LayoutMode, forWorkspace index: Int) {
        var stored = decode([Int: String].self, forKey: Key.tilingLayouts) ?? [:]
        stored[index] = mode.rawValue
        encode(stored, forKey: Key.tilingLayouts)
    }

    /// The modifier that stands in for Omarchy's SUPER key.
    ///
    /// ⌃⌘ by default rather than ⌥, which reads better but collides with Crest's
    /// own push-to-talk dictation on a machine where that is left on ⌥.
    static var tilingModifier: TilingModifier {
        get { TilingModifier(rawValue: defaults.string(forKey: Key.tilingModifier) ?? "") ?? .commandControl }
        set { defaults.set(newValue.rawValue, forKey: Key.tilingModifier) }
    }

    /// Keys the user rebound, by command id. Only the changes are stored, so a
    /// later release can move a default without having to migrate anything.
    static var tilingKeyOverrides: [String: HotKeyCombo] {
        get { decode([String: HotKeyCombo].self, forKey: Key.tilingKeyOverrides) ?? [:] }
        set { encode(newValue, forKey: Key.tilingKeyOverrides) }
    }

    private static func decode<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func encode(_ value: some Encodable, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    static var showFreeSpaceInMenuBar: Bool {
        get { defaults.object(forKey: Key.showFreeSpace) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.showFreeSpace) }
    }

    static var dockerEnabled: Bool {
        get { defaults.object(forKey: Key.dockerEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.dockerEnabled) }
    }

    static var homebrewEnabled: Bool {
        get { defaults.object(forKey: Key.homebrewEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.homebrewEnabled) }
    }

    static var policy: CleanerPolicy {
        get {
            guard let data = defaults.data(forKey: Key.policy),
                  let decoded = try? JSONDecoder().decode(CleanerPolicy.self, from: data)
            else { return .default }
            return decoded
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: Key.policy)
        }
    }

    static var selectedSection: PanelSection {
        get { PanelSection(rawValue: defaults.string(forKey: Key.selectedSection) ?? "") ?? .system }
        set { defaults.set(newValue.rawValue, forKey: Key.selectedSection) }
    }

    /// Backed by the login-item registration itself rather than a stored flag, so
    /// the toggle reflects reality even if the user changed it in System Settings.
    static var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                logger.error("Login item update failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

/// The figure shown in the menu bar. Only one fits without crowding the bar, so
/// it is a choice rather than a row of gauges.
enum MenuBarMetric: String, CaseIterable, Identifiable, Codable, Sendable {
    case freeSpace = "Free space"
    case cpu = "CPU"
    case memory = "Memory"
    case battery = "Battery"
    case none = "Icon only"

    var id: String { rawValue }
}

/// Menu-bar glyph options. Deliberately a fixed set of SF Symbols rather than a
/// free-form field: they are all template images that render correctly in both
/// menu-bar appearances and at the same optical weight as Apple's own items.
enum MenuBarIcon: String, CaseIterable, Identifiable, Codable, Sendable {
    case drive = "Drive"
    case gauge = "Gauge"
    case chart = "Chart"
    case sparkle = "Sparkle"
    case bolt = "Bolt"
    case circle = "Rings"
    case broom = "Cleanup"
    case cpu = "Chip"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .drive: "internaldrive.fill"
        case .gauge: "gauge.with.dots.needle.67percent"
        case .chart: "chart.bar.fill"
        case .sparkle: "sparkles"
        case .bolt: "bolt.fill"
        case .circle: "circle.dotted.circle"
        case .broom: "wand.and.sparkles"
        case .cpu: "cpu.fill"
        }
    }
}

/// Retained from the previous design because the disk ring and menu-bar tint both
/// key off it.
enum DiskHealthStatus: Equatable {
    case healthy
    case moderate
    case critical

    static func fromFreePercentage(_ freePercentage: Double) -> Self {
        if freePercentage > 20 { return .healthy }
        if freePercentage > 10 { return .moderate }
        return .critical
    }
}
