//
//  TilingObserver.swift
//  Crest
//

import AppKit
import ApplicationServices

/// Watches the system for the window events a tiler has to react to.
///
/// The alternative is polling — re-enumerating every window on a timer — and it is
/// the wrong trade twice over: each pass is a synchronous IPC round trip into every
/// running application, so a rate fast enough to feel immediate is a permanent tax
/// on battery, and one slow enough to be cheap leaves a visible pause between
/// opening a window and the layout admitting it exists. Accessibility will instead
/// call us, once, when something actually happens.
///
/// Only structural events are subscribed to. Window *moved* and *resized* are
/// deliberately absent: the tiler moves windows itself, so observing moves would
/// feed its own writes back to it as new input, and the loop that follows is a
/// window vibrating in place until the app is killed.
@MainActor
final class TilingObserver {

    /// Called when the set of windows, or which one is focused, may have changed.
    private let onChange: () -> Void

    private var observers: [pid_t: AXObserver] = [:]
    private var workspaceTokens: [NSObjectProtocol] = []

    private static let notifications = [
        kAXWindowCreatedNotification,
        kAXUIElementDestroyedNotification,
        kAXFocusedWindowChangedNotification,
        kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification,
        kAXApplicationHiddenNotification,
        kAXApplicationShownNotification,
    ]

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
    }

    deinit {
        for token in workspaceTokens {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
    }

    // MARK: - Lifecycle

    func start() {
        guard workspaceTokens.isEmpty else { return }

        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            observe(app)
        }

        let center = NSWorkspace.shared.notificationCenter
        // An app that launches after we started still needs watching, and one that
        // quits takes its windows with it — both change the layout.
        workspaceTokens = [
            center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { note in
                MainActor.assumeIsolated {
                    if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                        self.observe(app)
                    }
                    self.onChange()
                }
            },
            center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { note in
                MainActor.assumeIsolated {
                    if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                        self.observers.removeValue(forKey: app.processIdentifier)
                    }
                    self.onChange()
                }
            },
            center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { self.onChange() }
            },
            // Docking a laptop changes the screen the layout is computed against.
            NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
            ) { _ in
                MainActor.assumeIsolated { self.onChange() }
            },
        ]
    }

    func stop() {
        for (pid, observer) in observers {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
            observers.removeValue(forKey: pid)
        }
        for token in workspaceTokens {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        NotificationCenter.default.removeObserver(self)
        workspaceTokens = []
    }

    // MARK: - Per-application observers

    private func observe(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard app.activationPolicy == .regular,
              observers[pid] == nil,
              pid != ProcessInfo.processInfo.processIdentifier,
              !(app.bundleIdentifier.map(WindowEnumerator.neverTile.contains) ?? false)
        else { return }

        var observer: AXObserver?
        // The callback is a bare C function pointer with no captured context, so
        // the hop back to this object goes through the refcon below.
        let created = AXObserverCreate(pid, { _, _, _, refcon in
            guard let refcon else { return }
            let observer = Unmanaged<TilingObserver>.fromOpaque(refcon).takeUnretainedValue()
            Task { @MainActor in observer.onChange() }
        }, &observer)

        guard created == .success, let observer else { return }

        let element = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        var subscribed = false

        for notification in Self.notifications {
            // Apps that have not finished launching refuse subscriptions. Nothing
            // to recover here — the window-created event from the next app to come
            // up will trigger a refresh that picks this one's windows up anyway.
            if AXObserverAddNotification(observer, element, notification as CFString, refcon) == .success {
                subscribed = true
            }
        }

        guard subscribed else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer
    }
}
