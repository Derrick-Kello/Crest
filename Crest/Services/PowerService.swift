//
//  PowerService.swift
//  Crest
//

import Foundation
import IOKit
import IOKit.ps

struct PowerInfo: Sendable, Equatable {
    var hasBattery = false
    var percentage: Int = 0
    var isCharging = false
    var isPluggedIn = false
    var minutesRemaining: Int?

    var cycleCount: Int?
    var designCapacity: Int?
    var maxCapacity: Int?
    var temperatureCelsius: Double?
    /// Instantaneous draw in watts. Negative while charging, positive while running
    /// on battery — normalised to a magnitude plus `isCharging`.
    var watts: Double?
    var adapterWatts: Int?
    var condition: String?

    /// Present full-charge capacity as a share of the original design capacity.
    ///
    /// Expect this to sit a few points below the "Maximum Capacity" in System
    /// Settings. Apple's figure is smoothed over time and is not derivable from any
    /// IORegistry key — verified by checking every capacity value the battery
    /// publishes against it — so this reports the raw ratio and the UI says so.
    /// Third-party battery tools disagree with Settings for the same reason.
    var healthPercentage: Int? {
        guard let designCapacity, let maxCapacity, designCapacity > 0 else { return nil }
        return Int((Double(maxCapacity) / Double(designCapacity) * 100).rounded())
    }

    var timeRemainingDescription: String? {
        guard let minutesRemaining, minutesRemaining > 0 else { return nil }
        let hours = minutesRemaining / 60
        let minutes = minutesRemaining % 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    var statusDescription: String {
        if !hasBattery { return "Running on AC power" }
        if isCharging { return "Charging" }
        if isPluggedIn { return percentage >= 100 ? "Fully charged" : "Plugged in, not charging" }
        return "On battery"
    }
}

/// Battery and charging state, read from IOKit.
///
/// Two sources are combined: the IOPowerSources snapshot gives the live charge and
/// time estimate that macOS itself shows, while the AppleSmartBattery IORegistry
/// entry carries the things the power-source API omits — cycle count, design
/// capacity, temperature, and adapter wattage.
nonisolated final class PowerService: Sendable {
    static let shared = PowerService()

    func read() -> PowerInfo {
        var info = PowerInfo()
        readPowerSources(into: &info)
        readSmartBattery(into: &info)
        return info
    }

    private func readPowerSources(into info: inout PowerInfo) {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else { return }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?
                .takeUnretainedValue() as? [String: Any] else { continue }

            guard description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            info.hasBattery = true

            if let current = description[kIOPSCurrentCapacityKey] as? Int,
               let max = description[kIOPSMaxCapacityKey] as? Int, max > 0 {
                info.percentage = Int((Double(current) / Double(max) * 100).rounded())
            }

            let state = description[kIOPSPowerSourceStateKey] as? String
            info.isPluggedIn = state == kIOPSACPowerValue
            info.isCharging = description[kIOPSIsChargingKey] as? Bool ?? false

            // macOS reports -1 while it is still working out an estimate.
            let key = info.isCharging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
            if let minutes = description[key] as? Int, minutes > 0 {
                info.minutesRemaining = minutes
            }

            if let condition = description["BatteryHealthCondition"] as? String {
                info.condition = condition
            }
        }
    }

    private func readSmartBattery(into info: inout PowerInfo) {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSmartBattery")
        )
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }

        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let properties = unmanaged?.takeRetainedValue() as? [String: Any]
        else { return }

        info.hasBattery = true
        info.cycleCount = properties["CycleCount"] as? Int
        info.designCapacity = properties["DesignCapacity"] as? Int

        // Apple Silicon reports the real figure under NominalChargeCapacity;
        // AppleRawMaxCapacity is the Intel-era name for the same thing.
        info.maxCapacity = properties["NominalChargeCapacity"] as? Int
            ?? properties["AppleRawMaxCapacity"] as? Int
            ?? properties["MaxCapacity"] as? Int

        // Reported in hundredths of a degree Celsius.
        if let raw = properties["Temperature"] as? Int {
            info.temperatureCelsius = Double(raw) / 100
        }

        if let amperage = properties["Amperage"] as? Int,
           let voltage = properties["Voltage"] as? Int {
            // mA × mV → watts.
            info.watts = abs(Double(amperage) * Double(voltage) / 1_000_000)
        }

        if let adapter = properties["AdapterDetails"] as? [String: Any] {
            info.adapterWatts = adapter["Watts"] as? Int
        }
    }
}
