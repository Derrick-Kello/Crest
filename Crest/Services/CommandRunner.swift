//
//  CommandRunner.swift
//  Crest
//

import AppKit
import Foundation

/// Carries out a command bar action.
///
/// Split out from the view model so the routing lives next to the catalog that
/// defines it: adding an entry to `SystemCatalog` needs no matching `case` here,
/// because the action itself says what to do. Only `.appAction` goes back to the
/// view model, since those touch app state the runner has no business holding.
enum CommandRunner {

    /// Runs everything except `.appAction`, and reports what happened so the panel
    /// can show it. Returns nil when the caller has to handle the action itself.
    @MainActor
    @discardableResult
    static func run(_ action: CommandAction) -> String? {
        switch action {
        case .launchApp(let path):
            NSWorkspace.shared.openApplication(
                at: URL(fileURLWithPath: path),
                configuration: NSWorkspace.OpenConfiguration()
            )
            return nil

        case .openFile(let path):
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
            return nil

        case .revealInFinder(let path):
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            return nil

        case .openURL(let string):
            guard let url = URL(string: string) else { return nil }
            NSWorkspace.shared.open(url)
            return nil

        case .copyText(let text):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            return "Copied \(text.prefix(60))"

        case .shell(let command):
            // Always a literal from the catalog. Nothing typed into the search
            // field is ever interpolated into one of these strings.
            detach { _ = try? ProcessRunner.runShell(command) }
            return nil

        case .appleScript(let source):
            // `osascript` rather than `NSAppleScript`, which wants the main thread
            // and would block the UI for as long as the script takes — which for
            // "empty trash" on a full Trash is seconds, not milliseconds.
            detach { _ = try? ProcessRunner.run("/usr/bin/osascript", arguments: ["-e", source]) }
            return nil

        case .appAction:
            return nil
        }
    }

    /// Shells out off the main actor: these are all fire-and-forget, and none of
    /// them has a result the command bar shows.
    private static func detach(_ work: @escaping @Sendable () -> Void) {
        Task.detached(priority: .userInitiated, operation: work)
    }
}
