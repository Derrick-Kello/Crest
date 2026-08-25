//
//  AppSettings.swift
//  DiskPilot
//

import Foundation
import OSLog
import ServiceManagement

/// Thin, typed wrapper over `UserDefaults`. Every property reads and writes on
/// access — there is no in-memory mirror to fall out of sync with what's on disk.
enum Preferences {
    private static let defaults = UserDefaults.standard
    private static let logger = Logger(subsystem: "com.diskpilot", category: "Settings")

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
