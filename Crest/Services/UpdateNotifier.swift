//
//  UpdateNotifier.swift
//  Crest
//

import AppKit
import OSLog
import UserNotifications

/// Tells the user, once, that a newer Crest exists.
///
/// The background check has been running since the first release and had nowhere
/// to put its answer: the state landed in the About pane, which is behind a menu,
/// a window and a sidebar row, so in practice nobody found out about a release
/// unless they went looking for one. This is the part that comes to them.
///
/// Deliberately quiet. One notification per version, never repeated, and the
/// permission is not asked for at launch — a menu-bar utility that opens a system
/// prompt before it has done anything for you has not earned an answer yet. The
/// notification only ever links to the release page; Crest does not download or
/// replace itself.
@MainActor
final class UpdateNotifier: NSObject {
    static let shared = UpdateNotifier()

    private static let categoryID = "crest.update"
    private static let downloadActionID = "crest.update.download"

    private let logger = Logger(subsystem: "com.smarthive.crest", category: "Updates")
    private var isRegistered = false
    /// Set when the process has no bundle identity to post notifications with,
    /// which is the case for a raw binary run out of a build folder. Checked so
    /// the failure is logged once instead of on every check.
    private var isUnavailable = false

    private override init() { super.init() }

    /// Installs the delegate and the notification's action button.
    ///
    /// Has to happen at launch rather than at the point of use: macOS delivers a
    /// tap on a notification to whatever the delegate is *then*, and a Crest that
    /// only set one up after finding an update would drop the tap on a
    /// notification posted by the previous run.
    func configure() {
        guard !isRegistered, Bundle.main.bundleIdentifier != nil else { return }
        isRegistered = true

        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: Self.categoryID,
                actions: [
                    UNNotificationAction(
                        identifier: Self.downloadActionID,
                        title: "See what's new",
                        options: [.foreground]
                    ),
                ],
                intentIdentifiers: [],
                options: []
            ),
        ])
    }

    /// Whether the user has been asked yet, and what they said.
    func authorization() async -> UNAuthorizationStatus {
        guard Bundle.main.bundleIdentifier != nil else { return .denied }
        return await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Asks for permission, which shows the system prompt the first time only.
    @discardableResult
    func requestAuthorization() async -> Bool {
        configure()
        guard Bundle.main.bundleIdentifier != nil else { return false }
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        } catch {
            logger.error("Notification permission failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Posts the notification for a release, unless this one has already been
    /// announced.
    ///
    /// The version is recorded *before* the notification is posted rather than
    /// after. Posting can fail — permission refused, Do Not Disturb, no bundle
    /// identity — and retrying on the next check would mean a user who denied
    /// notifications gets a fresh prompt every day for the same release.
    func announce(version: String, url: URL, notes: String) async {
        guard Preferences.updateNotifications else { return }
        guard !isUnavailable, Bundle.main.bundleIdentifier != nil else { return }
        guard Preferences.announcedUpdateVersion != version else { return }

        let status = await authorization()
        switch status {
        case .denied:
            return
        case .notDetermined:
            // The one moment asking is fair: there is something specific to say,
            // and the prompt arrives attached to a reason.
            guard await requestAuthorization() else { return }
        default:
            configure()
        }

        Preferences.announcedUpdateVersion = version

        let content = UNMutableNotificationContent()
        content.title = "Crest \(version) is available"
        content.body = notes.isEmpty
            ? "You're on \(UpdateService.shared.currentVersion). Open the release page to see what changed."
            : notes
        content.categoryIdentifier = Self.categoryID
        content.userInfo = ["url": url.absoluteString]
        content.sound = .default

        do {
            try await UNUserNotificationCenter.current().add(
                UNNotificationRequest(
                    // One identifier per version, so a second check on the same
                    // day replaces the notification rather than stacking another
                    // copy of it under the first.
                    identifier: "crest.update.\(version)",
                    content: content,
                    trigger: nil
                )
            )
        } catch {
            isUnavailable = true
            logger.error("Couldn't post the update notification: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Forgets what has been announced, so the next check speaks up again. For the
    /// settings toggle: turning notifications back on and hearing nothing until
    /// the *next* release would look broken.
    func resetAnnouncements() {
        Preferences.announcedUpdateVersion = nil
    }
}

extension UpdateNotifier: UNUserNotificationCenterDelegate {

    /// Shows the banner even when Crest is frontmost.
    ///
    /// Crest is an accessory app, so "frontmost" here usually means the user has
    /// the command bar or the panel open — not that they are looking at anything
    /// that would tell them about a release. Suppressing the banner in that state,
    /// which is the default, would hide it exactly when it is most likely to be
    /// posted, since the background check runs at launch.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        guard let address = info["url"] as? String, let url = URL(string: address) else { return }
        // Dismissing is an answer too, and opening a browser for it would be
        // exactly the wrong one.
        guard response.actionIdentifier != UNNotificationDismissActionIdentifier else { return }
        await MainActor.run { NSWorkspace.shared.open(url) }
    }
}
