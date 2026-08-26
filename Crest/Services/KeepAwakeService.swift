//
//  KeepAwakeService.swift
//  Crest
//

import Foundation
import IOKit.pwr_mgt
import OSLog

/// How long a keep-awake session should hold.
enum KeepAwakeDuration: String, CaseIterable, Identifiable, Codable, Sendable {
    case indefinite = "Until I turn it off"
    case fifteenMinutes = "15 minutes"
    case oneHour = "1 hour"
    case twoHours = "2 hours"
    case eightHours = "8 hours"

    var id: String { rawValue }

    var seconds: TimeInterval? {
        switch self {
        case .indefinite: nil
        case .fifteenMinutes: 15 * 60
        case .oneHour: 3600
        case .twoHours: 2 * 3600
        case .eightHours: 8 * 3600
        }
    }

    var shortLabel: String {
        switch self {
        case .indefinite: "∞"
        case .fifteenMinutes: "15m"
        case .oneHour: "1h"
        case .twoHours: "2h"
        case .eightHours: "8h"
        }
    }
}

/// Holds an IOKit power assertion so the Mac stays awake.
///
/// This is the same mechanism `caffeinate` uses, and it needs no permissions and
/// no helper process. Two assertion types matter: preventing *system* idle sleep
/// keeps work running with the lid open, and additionally preventing *display*
/// idle sleep keeps the screen on — which the user should be able to opt out of,
/// since a lit screen overnight is its own problem.
@MainActor
@Observable
final class KeepAwakeService {
    static let shared = KeepAwakeService()

    private(set) var isActive = false
    private(set) var expiresAt: Date?

    var duration: KeepAwakeDuration = .indefinite
    /// When true the Mac stays awake but the display is allowed to sleep normally.
    var allowDisplaySleep = false

    private var systemAssertion: IOPMAssertionID = 0
    private var displayAssertion: IOPMAssertionID = 0
    private var expiryTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.silvergrade.crest", category: "KeepAwake")

    private init() {}

    var remainingDescription: String? {
        guard isActive, let expiresAt else { return nil }
        let remaining = expiresAt.timeIntervalSinceNow
        guard remaining > 0 else { return nil }
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m left" }
        if minutes > 0 { return "\(minutes)m left" }
        return "under a minute left"
    }

    func toggle() {
        isActive ? stop() : start()
    }

    func start() {
        stop(clearingState: false)

        let reason = "Crest Keep Awake" as CFString
        var created = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &systemAssertion
        )

        if !allowDisplaySleep {
            created = max(created, IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason,
                &displayAssertion
            ))
        }

        guard created == kIOReturnSuccess else {
            logger.error("Failed to create power assertion: \(created)")
            releaseAssertions()
            return
        }

        isActive = true

        if let seconds = duration.seconds {
            let deadline = Date().addingTimeInterval(seconds)
            expiresAt = deadline
            expiryTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled else { return }
                self?.stop()
            }
        } else {
            expiresAt = nil
        }

        logger.info("Keep awake on (\(self.duration.rawValue, privacy: .public))")
    }

    func stop() {
        stop(clearingState: true)
    }

    private func stop(clearingState: Bool) {
        expiryTask?.cancel()
        expiryTask = nil
        releaseAssertions()
        if clearingState {
            isActive = false
            expiresAt = nil
        }
    }

    private func releaseAssertions() {
        if systemAssertion != 0 {
            IOPMAssertionRelease(systemAssertion)
            systemAssertion = 0
        }
        if displayAssertion != 0 {
            IOPMAssertionRelease(displayAssertion)
            displayAssertion = 0
        }
    }
}
