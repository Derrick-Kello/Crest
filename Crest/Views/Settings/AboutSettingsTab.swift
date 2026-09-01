//
//  AboutSettingsTab.swift
//  Crest
//

import AppKit
import SwiftUI

/// What this build is, what it is allowed to touch, and whether a newer one exists.
struct AboutSettingsTab: View {
    @Environment(CrestViewModel.self) private var viewModel

    private let updates = UpdateService.shared

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 60, height: 60)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Crest")
                            .font(.system(size: 17, weight: .semibold))
                        Text("Version \(updates.currentVersion) (\(updates.buildNumber))")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Text("Storage, system load and cleanup, from the menu bar.")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()
                }
                .padding(.vertical, 4)
            }

            Section {
                HStack(spacing: 10) {
                    Button(updates.isChecking ? "Checking…" : "Check for updates") {
                        updates.check()
                    }
                    .disabled(updates.isChecking)

                    if updates.isChecking {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.7)
                    }

                    Spacer()

                    if case .available(_, let url, _) = updates.state {
                        Button("Download") { NSWorkspace.shared.open(url) }
                            .buttonStyle(.borderedProminent)
                    }
                }

                Toggle("Check automatically once a day", isOn: Binding(
                    get: { viewModel.automaticUpdateChecks },
                    set: { viewModel.automaticUpdateChecks = $0 }
                ))

                Toggle("Notify me when there's a new version", isOn: Binding(
                    get: { viewModel.updateNotifications },
                    set: { viewModel.updateNotifications = $0 }
                ))
                .disabled(!viewModel.automaticUpdateChecks)
            } header: {
                Text("Updates")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    updateFooter
                    Text("One notification per release, never repeated. macOS asks for permission the first time there is something to say.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                LabeledContent("Onboarding") {
                    Button("Show again") { viewModel.replayOnboarding() }
                }
                link("Source and releases", "https://github.com/Derrick-Kello/Crest")
                link("Report a problem", "https://github.com/Derrick-Kello/Crest/issues/new")
            } header: {
                Text("Help")
            }

            Section {
                Text("""
                Crest reads your home folder and the caches your developer tools leave behind. \
                It never touches system files, everything it removes goes to the Trash, and nothing \
                it indexes — apps, files, clipboard, or anything you type into the command bar — \
                leaves this Mac. The only network request it ever makes is the update check above.
                """)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Privacy")
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
        .task { updates.checkInBackgroundIfDue() }
    }

    @ViewBuilder
    private var updateFooter: some View {
        switch updates.state {
        case .idle:
            if let last = updates.lastChecked {
                Text("Last checked \(last.formatted(.relative(presentation: .named))).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Releases are published on GitHub. Crest never installs anything by itself — the button opens the release page.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .checking:
            Text("Asking GitHub for the latest release…")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .upToDate:
            Label("You're on the latest version.", systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.green)
        case .noReleases:
            Label("No releases published yet — this build is the newest there is.", systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .available(let version, _, let notes):
            VStack(alignment: .leading, spacing: 3) {
                Label("Version \(version) is available.", systemImage: "arrow.down.circle")
                    .font(.caption)
                    .foregroundStyle(.tint)
                if !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    private func link(_ title: String, _ address: String) -> some View {
        LabeledContent(title) {
            Button("Open") {
                guard let url = URL(string: address) else { return }
                NSWorkspace.shared.open(url)
            }
        }
    }
}
