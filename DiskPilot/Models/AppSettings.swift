//
//  AppSettings.swift
//  DiskPilot
//

import Foundation

enum CleanupSafetyLevel: String, CaseIterable, Identifiable, Codable {
    case conservative = "Conservative"
    case balanced = "Balanced"
    case aggressive = "Aggressive"

    var id: String { rawValue }
}

enum AppSettingsStorage {
    private enum Keys {
        static let menuBarEnabled = "menuBarEnabled"
        static let autoScanInterval = "autoScanInterval"
        static let safetyLevel = "safetyLevel"
        static let dockerEnabled = "dockerEnabled"
    }

    static func load() -> (
        menuBarEnabled: Bool,
        autoScanIntervalSeconds: Int,
        safetyLevel: CleanupSafetyLevel,
        dockerIntegrationEnabled: Bool
    ) {
        let defaults = UserDefaults.standard
        let menuBarEnabled = defaults.object(forKey: Keys.menuBarEnabled) as? Bool ?? true
        let autoScanIntervalSeconds = defaults.object(forKey: Keys.autoScanInterval) as? Int ?? 300
        let levelRaw = defaults.string(forKey: Keys.safetyLevel) ?? CleanupSafetyLevel.balanced.rawValue
        let safetyLevel = CleanupSafetyLevel(rawValue: levelRaw) ?? .balanced
        let dockerIntegrationEnabled = defaults.object(forKey: Keys.dockerEnabled) as? Bool ?? true
        return (menuBarEnabled, autoScanIntervalSeconds, safetyLevel, dockerIntegrationEnabled)
    }

    static func save(
        menuBarEnabled: Bool,
        autoScanIntervalSeconds: Int,
        safetyLevel: CleanupSafetyLevel,
        dockerIntegrationEnabled: Bool
    ) {
        let defaults = UserDefaults.standard
        defaults.set(menuBarEnabled, forKey: Keys.menuBarEnabled)
        defaults.set(autoScanIntervalSeconds, forKey: Keys.autoScanInterval)
        defaults.set(safetyLevel.rawValue, forKey: Keys.safetyLevel)
        defaults.set(dockerIntegrationEnabled, forKey: Keys.dockerEnabled)
    }
}
