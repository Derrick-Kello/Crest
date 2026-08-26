//
//  VoiceSectionView.swift
//  Crest
//

import AVFoundation
import AppKit
import SwiftUI

/// The Voice tab: what dictation is doing, and what it has done.
///
/// The recording itself happens in the floating HUD, not here — by the time you are
/// talking, the panel has closed and you are looking at your own text field. So this tab
/// is for the two things you come back for: checking the setup is right, and getting at
/// something you dictated a minute ago.
struct VoiceSectionView: View {
    @Environment(CrestViewModel.self) private var viewModel

    var body: some View {
        PanelCard(section: .voice) {
            if viewModel.voiceEnabled {
                Text(Preferences.pushToTalkKey.displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                if !viewModel.voiceEnabled {
                    disabledState
                } else {
                    activeState
                }
            }
        }
    }

    // MARK: - States

    private var disabledState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hold a key, talk, and cleaned-up text lands wherever you're typing. Everything runs on this Mac.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Needs Accessibility, to see the key you hold, and the microphone.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Turn on dictation") {
                viewModel.voiceEnabled = true
                VoicePermissions.promptForAccessibility()
            }
            .controlSize(.small)
        }
    }

    /// The two grants, listed while either is missing.
    ///
    /// Both are shown together rather than one gating the other. An earlier version hid
    /// everything behind Accessibility, which meant the microphone was never asked for:
    /// the only two places that request it are a recording starting, and a recording
    /// could not start, so the prompt had no way to ever appear.
    @ViewBuilder
    private var permissionChecklist: some View {
        let needsMic = viewModel.dictation.microphoneAccess != .authorized
        let needsAccessibility = viewModel.dictation.needsAccessibility

        if needsMic || needsAccessibility {
            VStack(alignment: .leading, spacing: 6) {
                if needsMic {
                    permissionRow(
                        title: "Microphone",
                        detail: "So Crest can hear you",
                        button: viewModel.dictation.microphoneAccess == .denied ? "Open Settings" : "Allow"
                    ) {
                        Task { await viewModel.dictation.requestMicrophoneAccess() }
                    }
                }
                if needsAccessibility {
                    permissionRow(
                        title: "Accessibility",
                        detail: "So it can see the key you hold, and type the result",
                        button: "Open Settings"
                    ) {
                        VoicePermissions.promptForAccessibility()
                        VoicePermissions.openAccessibilitySettings()
                    }

                    // The one failure nobody can diagnose from the outside. Worth the
                    // three lines: without them the user sees a switch that is already
                    // on, an app that says it is off, and no way to reconcile them.
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Already switched on over there? The entry is left over from an earlier build. Toggling it won't help — the row has to go.")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Button("Clear it and ask again") {
                            VoicePermissions.resetAccessibilityGrant()
                            viewModel.dictation.refreshPermissions()
                            VoicePermissions.promptForAccessibility()
                        }
                        .controlSize(.small)
                    }
                    .padding(.leading, 18)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.12), in: .rect(cornerRadius: 9))
        }
    }

    private func permissionRow(
        title: String,
        detail: String,
        button: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                Text(detail)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Button(button, action: action)
                .controlSize(.small)
        }
    }

    private var activeState: some View {
        VStack(alignment: .leading, spacing: 10) {
            permissionChecklist

            recordButton

            // Capture and transcription work without Accessibility; only the typing does
            // not. Saying so beats a Record button that appears to work and then puts the
            // words nowhere.
            if viewModel.dictation.needsAccessibility {
                Text("Until Accessibility is on, the key you hold does nothing and dictations are kept here to copy instead of typed.")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            statistics

            if !viewModel.voiceHistory.entries.isEmpty {
                Divider()
                recent
            }
        }
        // TCC changes happen in System Settings, which this process cannot observe, so
        // the state is re-read whenever the panel comes back into view.
        .onAppear { viewModel.dictation.refreshPermissions() }
    }

    private var recordButton: some View {
        let isRecording = viewModel.dictation.phase.isRecording

        return Button {
            viewModel.toggleDictation()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: isRecording ? "stop.circle.fill" : "mic.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(isRecording ? AnyShapeStyle(.red) : AnyShapeStyle(.tint))
                VStack(alignment: .leading, spacing: 1) {
                    Text(isRecording ? "Stop and type it" : "Start dictating")
                        .font(.system(size: 12, weight: .medium))
                    Text(isRecording
                         ? "Recording"
                         : "or hold \(Preferences.pushToTalkKey.displayName) anywhere")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if isRecording {
                    VoiceWaveform(level: viewModel.dictation.level, isActive: true, barCount: 6)
                        .frame(width: 34, height: 18)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 9))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// What dictation has actually bought you.
    ///
    /// The headline is time against typing, because that is the only reason to dictate
    /// and the only figure worth putting first. It is signed, and it prints the typing
    /// speed it was measured against — a saving quoted without its assumption is a
    /// number the user has no way to argue with.
    @ViewBuilder
    private var statistics: some View {
        let stats = viewModel.voiceHistory.analytics(
            typingWordsPerMinute: viewModel.typingWordsPerMinute
        )

        if stats.isEmpty {
            Text("Figures appear here once you've dictated something.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        } else {
            VStack(alignment: .leading, spacing: 9) {
                PanelHeadlineFigure(
                    symbolName: stats.timeSaved >= 0 ? "hare" : "tortoise",
                    value: DurationText.string(stats.timeSaved) + (stats.timeSaved >= 0 ? " saved" : " slower"),
                    caption: "against typing \(stats.words.formatted()) words at \(stats.typingWordsPerMinute) wpm"
                )

                Divider()

                PanelFigureRow(figures: figures(stats))

                if let footnote = footnote(stats) {
                    Text(footnote)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.25), in: .rect(cornerRadius: 9))
        }
    }

    private func figures(_ stats: DictationAnalytics) -> [PanelFigureRow.Figure] {
        var figures: [PanelFigureRow.Figure] = [
            .init(value: "\(stats.count)", label: "dictations"),
            .init(value: stats.words.formatted(.number.notation(.compactName)), label: "words"),
        ]
        if let rate = stats.speakingRate {
            figures.append(.init(value: "\(rate)", label: "wpm"))
        }
        if let latency = stats.medianLatency {
            figures.append(.init(value: String(format: "%.1fs", latency), label: "to type"))
        }
        return figures
    }

    /// The two things that are only interesting once they are true: where you dictate
    /// most, and whether the vocabulary is earning its place.
    private func footnote(_ stats: DictationAnalytics) -> String? {
        var parts: [String] = []
        if stats.countToday > 0 { parts.append("\(stats.countToday) today") }
        if let application = stats.topApplication, stats.topApplicationCount > 1 {
            parts.append("mostly in \(application)")
        }
        if stats.corrections > 0 {
            parts.append("vocabulary fixed \(stats.corrections)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: PanelMetrics.rowSpacing) {
            HStack {
                Text("Recent")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Clear") { viewModel.voiceHistory.clear() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            ForEach(viewModel.voiceHistory.entries.prefix(4)) { entry in
                DictationRow(entry: entry)
            }
        }
    }
}

/// One history row. Clicking copies it, which is the only thing anyone wants from a
/// transcript they can already see — usually because it landed in the wrong window.
private struct DictationRow: View {
    let entry: Dictation
    @State private var didCopy = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(entry.text, forType: .string)
            withAnimation(.snappy(duration: 0.15)) { didCopy = true }
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                withAnimation(.snappy(duration: 0.15)) { didCopy = false }
            }
        } label: {
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: didCopy ? "checkmark.circle.fill" : entry.style.symbolName)
                    .font(.system(size: 10))
                    .foregroundStyle(didCopy ? AnyShapeStyle(.green) : AnyShapeStyle(.tertiary))
                    .frame(width: 14)
                    .padding(.top, 1)
                    .contentTransition(.symbolEffect(.replace))

                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.text)
                        .font(.system(size: 11))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(.primary)

                    HStack(spacing: 4) {
                        if let app = entry.appName {
                            Text(app)
                        }
                        Text(entry.date, style: .relative)
                        if entry.wordsPerMinute > 0 {
                            Text("· \(entry.wordsPerMinute) wpm")
                        }
                    }
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("Copy this dictation")
    }
}
