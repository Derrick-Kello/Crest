//
//  VoiceSettingsTab.swift
//  Crest
//

import AVFoundation
import AppKit
import SwiftUI

/// Everything voice: dictation, the vocabulary, and meeting notes.
///
/// One pane rather than two because the two features share their machinery and their
/// permissions, and splitting them would mean explaining the microphone twice and
/// leaving the user to work out that the vocabulary they taught dictation also applies
/// to their meetings.
struct VoiceSettingsTab: View {
    @Environment(CrestViewModel.self) private var viewModel

    var body: some View {
        @Bindable var viewModel = viewModel

        Form {
            dictationSection(viewModel)
            if viewModel.voiceEnabled {
                permissionsSection
                styleSection(viewModel)
                measurementSection(viewModel)
                commandModeSection(viewModel)
                VocabularySection()
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
        // TCC state changes in System Settings, which this process cannot observe. The
        // pane re-reads it on appear so a grant made a moment ago is not shown as
        // missing.
        .onAppear { viewModel.dictation.refreshPermissions() }
    }

    // MARK: - Dictation

    private func dictationSection(_ viewModel: CrestViewModel) -> some View {
        @Bindable var viewModel = viewModel

        return Section {
            Toggle("Dictation", isOn: $viewModel.voiceEnabled)

            if viewModel.voiceEnabled {
                Picker("Hold to talk", selection: $viewModel.pushToTalkKey) {
                    ForEach(PushToTalkKey.allCases) { key in
                        Text(key.displayName).tag(key)
                    }
                }

                Toggle("A quick tap keeps the mic open", isOn: $viewModel.voiceHandsFree)
                Toggle("Play a sound when recording starts and stops", isOn: $viewModel.voiceSound)
                Toggle("Learn the names of your apps", isOn: $viewModel.voiceLearnAppNames)
            }
        } header: {
            Text("Dictation")
        } footer: {
            Text(viewModel.voiceEnabled
                 ? "Hold the key, talk, let go, and the text is typed where your cursor is. Press Escape while recording to throw it away. A modifier is used rather than a normal shortcut because push-to-talk needs to see the key go down and come back up, which the shortcut system never reports."
                 : "Hold a key anywhere on the Mac, talk, and cleaned-up text lands in whatever you're typing into. Speech recognition and cleanup both run on this Mac; nothing is uploaded.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Permissions

    private var permissionsSection: some View {
        Section {
            PermissionRow(
                title: "Accessibility",
                detail: "Sees the key you hold, and types the result",
                isGranted: !viewModel.dictation.needsAccessibility && VoicePermissions.hasAccessibility
            ) {
                VoicePermissions.promptForAccessibility()
                VoicePermissions.openAccessibilitySettings()
            }

            if viewModel.dictation.needsAccessibility || !VoicePermissions.hasAccessibility {
                LabeledContent {
                    Button("Clear and ask again") {
                        VoicePermissions.resetAccessibilityGrant()
                        viewModel.dictation.refreshPermissions()
                        VoicePermissions.promptForAccessibility()
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Switched on but still not working?")
                        Text("Drops the leftover entries and asks cleanly")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            PermissionRow(
                title: "Microphone",
                detail: "Hears you",
                isGranted: viewModel.dictation.microphoneAccess == .authorized,
                // An app that has never asked is not in the Microphone list in System
                // Settings, so sending a first-time user there shows them a list without
                // Crest in it. Ask first; the pane is only useful after a denial.
                buttonTitle: viewModel.dictation.microphoneAccess == .denied ? "Open Settings" : "Allow"
            ) {
                Task { await viewModel.dictation.requestMicrophoneAccess() }
            }
        } header: {
            Text("Permissions")
        } footer: {
            Text("macOS ties each grant to Crest's code signature, and an unsigned build gets a new signature every time it is compiled — so a rebuilt Crest stops satisfying the grant given to the previous one. When that happens the Accessibility switch still reads as on while the app is reported untrusted, and toggling it changes nothing, because the leftover entry is the problem. Clearing it and asking again is the fix. Signing with a Developer ID certificate ends this for good.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Style

    private func styleSection(_ viewModel: CrestViewModel) -> some View {
        @Bindable var viewModel = viewModel

        return Section {
            Picker("Cleanup", selection: $viewModel.dictationCleanup) {
                ForEach(CleanupMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text(viewModel.dictationCleanup.blurb)
                .font(.caption)
                .foregroundStyle(.secondary)

            if viewModel.dictationCleanup == .model, let reason = ModelCleanup.unavailableReason {
                Label(reason + " Dictation falls back to the instant pass.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Picker("Write like", selection: Binding(
                get: { viewModel.dictationStyle },
                set: { viewModel.dictationStyle = $0 }
            )) {
                Text("Whatever suits the app").tag(DictationStyle?.none)
                Divider()
                ForEach(DictationStyle.allCases) { style in
                    Text(style.title).tag(DictationStyle?.some(style))
                }
            }

            if let style = viewModel.dictationStyle {
                Text(style.blurb)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            StyleOverrideList()
        } header: {
            Text("How it writes")
        } footer: {
            Text("Left to itself, Crest picks a style from whichever app is in front: full sentences in Mail, no trailing full stop in Slack, and nothing capitalized or punctuated in a terminal, where an added full stop is a syntax error.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Measurement

    private func measurementSection(_ viewModel: CrestViewModel) -> some View {
        @Bindable var viewModel = viewModel

        return Section {
            Picker("You type at about", selection: $viewModel.typingWordsPerMinute) {
                Text("30 wpm").tag(30)
                Text("40 wpm — average").tag(40)
                Text("60 wpm").tag(60)
                Text("80 wpm — fast").tag(80)
                Text("100 wpm — very fast").tag(100)
            }
        } header: {
            Text("Time saved")
        } footer: {
            Text("The Voice tab compares what your dictated words would have cost to type against what they actually cost, which is the time you held the key plus the wait for the text. That comparison is only as good as this number, so it is yours to set rather than something Crest assumes and never shows you.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Command mode

    private func commandModeSection(_ viewModel: CrestViewModel) -> some View {
        @Bindable var viewModel = viewModel

        return Section {
            Toggle("Rewrite selected text by voice", isOn: $viewModel.commandModeEnabled)

            if viewModel.commandModeEnabled {
                Picker("Hold to rewrite", selection: $viewModel.commandModeKey) {
                    ForEach(PushToTalkKey.allCases) { key in
                        Text(key.displayName).tag(key)
                    }
                }
                .disabled(false)

                if viewModel.commandModeKey == viewModel.pushToTalkKey {
                    Label("That's the same key as dictation. Pick a different one.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        } header: {
            Text("Command mode")
        } footer: {
            Text("Select text anywhere, hold the key, and say what to do with it — \"make this shorter\", \"turn this into bullet points\". The selection is replaced. Runs on the same on-device model as smart cleanup.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// One permission, its state, and the one button that can change it.
private struct PermissionRow: View {
    let title: String
    let detail: String
    let isGranted: Bool
    var buttonTitle = "Grant"
    let action: () -> Void

    var body: some View {
        LabeledContent {
            HStack(spacing: 10) {
                Label(
                    isGranted ? "Granted" : "Not granted",
                    systemImage: isGranted ? "checkmark.circle.fill" : "xmark.circle"
                )
                .font(.caption)
                .foregroundStyle(isGranted ? .green : .orange)

                if !isGranted {
                    Button(buttonTitle, action: action)
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// The apps that have been pinned to a style, with a way to unpin them.
///
/// Additive only: a style is pinned from the panel's history rows, where the app is
/// right there in front of you, rather than by picking an app out of a list here.
private struct StyleOverrideList: View {
    @Environment(CrestViewModel.self) private var viewModel
    @State private var overrides: [String: DictationStyle] = Preferences.dictationStyleOverrides

    var body: some View {
        if !overrides.isEmpty {
            ForEach(overrides.sorted(by: { $0.key < $1.key }), id: \.key) { identifier, style in
                LabeledContent(Self.name(for: identifier)) {
                    HStack(spacing: 8) {
                        Text(style.title).foregroundStyle(.secondary)
                        Button("Reset") {
                            viewModel.dictation.setStyle(nil, forBundleIdentifier: identifier)
                            overrides = Preferences.dictationStyleOverrides
                        }
                    }
                }
            }
        }
    }

    /// The app's real name where macOS still knows it, and the bundle identifier where
    /// the app has since been deleted — which is exactly when you want to remove the row.
    private static func name(for identifier: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) else {
            return identifier
        }
        return FileManager.default.displayName(atPath: url.path)
    }
}

/// The words the recognizer is told about, and the mishearings it should rewrite.
private struct VocabularySection: View {
    @Environment(CrestViewModel.self) private var viewModel

    @State private var heard = ""
    @State private var written = ""

    var body: some View {
        Section {
            ForEach(viewModel.vocabulary.entries.filter { !$0.isAutomatic }) { entry in
                LabeledContent {
                    HStack(spacing: 8) {
                        Toggle("", isOn: Binding(
                            get: { entry.isEnabled },
                            set: { viewModel.vocabulary.setEnabled($0, for: entry) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)

                        Button {
                            viewModel.vocabulary.delete(entry)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                } label: {
                    if entry.kind == .correction {
                        Text("\(entry.hear)  →  \(entry.write)")
                            .font(.system(size: 12, design: .monospaced))
                    } else {
                        Text(entry.write)
                    }
                }
            }

            HStack(spacing: 8) {
                TextField("Heard as (optional)", text: $heard)
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                TextField("Written as", text: $written)
                Button("Add", action: add)
                    .disabled(written.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            LabeledContent("Learned from your apps") {
                HStack(spacing: 10) {
                    Text("\(viewModel.vocabulary.entries.count(where: \.isAutomatic)) names")
                        .foregroundStyle(.secondary)
                    Button("Open the file") {
                        NSWorkspace.shared.activateFileViewerSelecting([VocabularyStore.fileURL])
                    }
                }
            }
        } header: {
            Text("Vocabulary")
        } footer: {
            Text("A name on its own tells the recognizer the word exists. A pair rewrites one into the other after the fact, which is the half that is guaranteed — biasing only improves the odds. It's a plain text file you can edit directly; Crest picks up changes immediately.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func add() {
        let write = written.trimmingCharacters(in: .whitespacesAndNewlines)
        let hear = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !write.isEmpty else { return }

        viewModel.vocabulary.add(
            hear.isEmpty ? .term(write) : .correction(hear: hear, write: write)
        )
        heard = ""
        written = ""
    }
}
