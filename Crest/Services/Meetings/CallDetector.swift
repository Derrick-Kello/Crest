//
//  CallDetector.swift
//  Crest
//

import AppKit
import CoreAudio
import Foundation
import OSLog

/// Notices when you are probably in a call, so Crest can offer to take notes instead
/// of relying on you to remember before the meeting starts — which is exactly when
/// nobody remembers.
///
/// Two signals, and both have to agree:
///
/// 1. **A call app is running.** Cheap to check and specific, but a launched Zoom that
///    has been idle in the Dock since Tuesday is not a meeting.
/// 2. **Something is using the microphone.** This is the signal that actually means a
///    call, and it comes from CoreAudio rather than from any app's cooperation.
///
/// Requiring both keeps the suggestion off the screen while you are dictating into a
/// voice memo, and off the screen while Teams merely exists.
@MainActor
@Observable
final class CallDetector {
    /// The app that looks like it is in a call, or nil.
    private(set) var activeCallApplication: String?

    private var pollTask: Task<Void, Never>?
    /// Suppressed for the rest of this call once the user says no, so declining is not
    /// something they have to keep doing every thirty seconds.
    private var dismissedApplication: String?

    /// Called when a call starts and has not been dismissed. Wired to the offer.
    var onCallDetected: ((String) -> Void)?

    /// Bundle identifier prefixes for apps that hold meetings. Prefixes rather than exact
    /// identifiers because Teams, Zoom and Webex each ship several bundles and rename
    /// them between releases.
    private static let callApplications: [(prefix: String, name: String)] = [
        ("us.zoom.xos", "Zoom"),
        ("com.microsoft.teams", "Microsoft Teams"),
        ("com.cisco.webexmeetingsapp", "Webex"),
        ("com.cisco.webex", "Webex"),
        ("com.tinyspeck.slackmacgap", "Slack"),
        ("com.hnc.discord", "Discord"),
        ("com.apple.facetime", "FaceTime"),
        ("com.google.meet", "Google Meet"),
        ("com.loom.desktop", "Loom"),
        ("com.readdle.spark", "Spark"),
        ("com.around.around", "Around"),
        ("com.gotomeeting", "GoTo Meeting"),
        ("com.skype", "Skype"),
    ]

    // MARK: - Polling

    /// Every eight seconds. A meeting that has been running for eight seconds has not
    /// gone anywhere, and this is a background check on a machine the user is using for
    /// something else.
    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.poll()
                try? await Task.sleep(for: .seconds(8))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        activeCallApplication = nil
    }

    /// Stops offering for the current call.
    func dismissCurrent() {
        dismissedApplication = activeCallApplication
    }

    private func poll() {
        guard Preferences.meetingSuggestOnCall else {
            activeCallApplication = nil
            return
        }

        guard let name = Self.runningCallApplication(), Self.microphoneIsInUse() else {
            activeCallApplication = nil
            // The call ended, so a previous "no thanks" should not silence the next one.
            dismissedApplication = nil
            return
        }

        let wasActive = activeCallApplication != nil
        activeCallApplication = name
        guard !wasActive, dismissedApplication != name else { return }
        VoiceLog.meeting.info("call detected in \(name, privacy: .public)")
        onCallDetected?(name)
    }

    // MARK: - Signals

    static func runningCallApplication() -> String? {
        for application in NSWorkspace.shared.runningApplications {
            guard let identifier = application.bundleIdentifier?.lowercased() else { continue }
            if let match = callApplications.first(where: { identifier.hasPrefix($0.prefix) }) {
                return application.localizedName ?? match.name
            }
        }
        return nil
    }

    /// True when *any* process is running the default input device.
    ///
    /// `kAudioDevicePropertyDeviceIsRunningSomewhere` is the only reading here that does
    /// not depend on an app cooperating: it is the hardware's own view of whether the
    /// microphone is live, which is what a call actually is.
    static func microphoneIsInUse() -> Bool {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        ) == noErr, deviceID != kAudioObjectUnknown else { return false }

        var isRunning = UInt32(0)
        var runningSize = UInt32(MemoryLayout<UInt32>.size)
        var runningAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectGetPropertyData(
            deviceID, &runningAddress, 0, nil, &runningSize, &isRunning
        ) == noErr else { return false }

        return isRunning != 0
    }
}
