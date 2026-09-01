//
//  CommandBarSettingsTab.swift
//  Crest
//

import AppKit
import SwiftUI

/// The command bar, on its own pane.
///
/// It used to be one section at the top of Shortcuts, under a header that said
/// "Command bar" and gave no indication that the feature was the fastest way into
/// most of what Crest does. Somebody who never opened that pane — and the pane is
/// called Shortcuts, so somebody who is not looking to bind a key never does —
/// could use Crest for a week without finding out it had a launcher at all.
///
/// So it gets a row in the sidebar and a picture of itself. The preview is the
/// point: a shortcut in a settings row tells you a key exists, and a picture of
/// what it opens tells you whether you want it.
struct CommandBarSettingsTab: View {
    @Environment(CrestViewModel.self) private var viewModel

    private let service = UserHotKeyService.shared

    var body: some View {
        @Bindable var viewModel = viewModel

        Form {
            Section {
                CommandBarPreview(shortcut: viewModel.commandBarHotKey.displayString)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section {
                Toggle("Enable the command bar", isOn: $viewModel.commandBarEnabled)

                LabeledContent("Shortcut") {
                    ShortcutRecorder(
                        combo: Binding(
                            get: { viewModel.commandBarHotKey },
                            set: { if let combo = $0 { viewModel.commandBarHotKey = combo } }
                        ),
                        conflict: { combo in
                            service.hotKeys.first { $0.combo == combo }?.name
                        },
                        placeholder: "Click to record"
                    )
                    .frame(width: 150, height: 22)
                    .disabled(!viewModel.commandBarEnabled)
                }
            } header: {
                Text("Opening it")
            } footer: {
                if viewModel.hotKeyRegistrationFailed {
                    Text("\(viewModel.commandBarHotKey.displayString) is already claimed by another app. Record a different one.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Text("Search apps, run Crest actions, switch workspaces, do arithmetic, preview files, or paste from clipboard history. Press \(viewModel.commandBarHotKey.displayString) from anywhere.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Toggle("Search files as well as apps", isOn: $viewModel.fileSearchEnabled)
                Toggle("Preview the selected file", isOn: $viewModel.filePreviewEnabled)
                    .disabled(!viewModel.fileSearchEnabled)
            } header: {
                Text("Files and folders")
            } footer: {
                Text("Your folders are indexed at launch and answer instantly. Files come from the Spotlight index macOS already keeps, so there is no second index and nothing to wait for. Build output, caches and dependency folders are left out of both. ⌘↩ reveals in Finder, ⌘⇧C copies the path.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(Self.scopes, id: \.keys) { scope in
                    LabeledContent {
                        Text(scope.what)
                            .foregroundStyle(.secondary)
                    } label: {
                        Text(scope.keys)
                            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    }
                }
            } header: {
                Text("Narrowing a search")
            } footer: {
                Text("Everything else is a plain search across apps, settings, folders, files and Crest's own actions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(Self.tips, id: \.keys) { tip in
                    LabeledContent {
                        Text(tip.keys)
                            .font(.system(size: 11.5, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    } label: {
                        Text(tip.what)
                    }
                }
            } header: {
                Text("While it's open")
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }

    private static let scopes: [(keys: String, what: String)] = [
        ("d ", "Folders only"),
        ("f ", "Files only"),
        ("~/ or /", "Jump straight to that exact path"),
    ]

    private static let tips: [(keys: String, what: String)] = [
        ("↑ ↓", "Move through the results"),
        ("↩", "Run the selected result"),
        ("⌘↩", "Reveal the selected file in Finder"),
        ("⌘⇧C", "Copy the selected file's path"),
        ("⎋", "Close the bar"),
    ]
}

/// A picture of the command bar, drawn with the same chrome as the real one.
///
/// Not a screenshot: a screenshot is taken in one appearance and one accent colour
/// and is wrong in every other. This follows whatever the Mac is set to, which is
/// most of what the preview is there to show.
private struct CommandBarPreview: View {
    let shortcut: String

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("terminal")
                    .font(.system(size: 14))
                Spacer()
                Text(shortcut)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .frame(height: 44)

            Rectangle()
                .fill(.primary.opacity(0.08))
                .frame(height: 1)

            VStack(spacing: 0) {
                row("Terminal", "Applications", "terminal", selected: true)
                row("Toggle Window Tiling", "Arrange windows side by side, or stop", "rectangle.split.2x2", selected: false)
            }
            .padding(.vertical, 4)
        }
        .commandBarSurface(cornerRadius: 12)
        .padding(.horizontal, 10)
        .padding(.vertical, 14)
        // The glass refracts whatever is behind it, and a settings form is a flat
        // grey — so the preview is given something to refract. Without this the
        // effect is technically present and completely invisible.
        .background {
            LinearGradient(
                colors: [.accentColor.opacity(0.55), .purple.opacity(0.35), .teal.opacity(0.35)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .clipShape(.rect(cornerRadius: 10))
        .accessibilityHidden(true)
    }

    private func row(_ title: String, _ subtitle: String, _ symbol: String, selected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .frame(width: 20)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12))
                Text(subtitle).font(.system(size: 9.5)).foregroundStyle(.secondary)
            }

            Spacer(minLength: 6)

            if selected {
                Text("Open ↩")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background {
            if selected {
                CommandBarSelection().padding(.horizontal, 6)
            }
        }
    }
}
