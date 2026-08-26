//
//  MeetingsSettingsTab.swift
//  Crest
//

import AppKit
import AVFoundation
import SwiftUI

/// Meeting notes, on its own pane.
///
/// Split out from Voice because the two features are only related by the machinery
/// underneath them. Dictation is a typing tool you reach for a hundred times a day;
/// meeting notes is a recorder that produces documents and accumulates files. They have
/// different settings, different risks, and different things worth saying — folding them
/// together meant explaining recording consent in a footnote under a keyboard shortcut.
struct MeetingsSettingsTab: View {
    @Environment(CrestViewModel.self) private var viewModel

    var body: some View {
        @Bindable var viewModel = viewModel

        Form {
            Section {
                Toggle("Meeting notes", isOn: $viewModel.meetingsEnabled)
            } footer: {
                Text("Records your microphone and the Mac's own output as two separate streams, transcribes each of them, and writes the summary here on this Mac. No bot joins the call and nothing is uploaded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if viewModel.meetingsEnabled {
                captureSection(viewModel)
                permissionsSection
                summarySection(viewModel)
                storageSection
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
        .onAppear { viewModel.dictation.refreshPermissions() }
    }

    // MARK: - Capture

    private func captureSection(_ viewModel: CrestViewModel) -> some View {
        @Bindable var viewModel = viewModel

        return Section {
            Toggle("Record your microphone", isOn: $viewModel.meetingCaptureMicrophone)
            Toggle("Record what the Mac is playing", isOn: $viewModel.meetingCaptureSystemAudio)
            Toggle("Offer to take notes when a call starts", isOn: $viewModel.meetingSuggestOnCall)
        } header: {
            Text("What gets recorded")
        } footer: {
            Text("Capturing the two separately is what lets the transcript say who spoke without guessing at it. Turn one off and the transcript keeps the other, labelled honestly rather than pretending it heard the room. The offer appears only when a call app is running and something is actually holding the microphone.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Permissions

    private var permissionsSection: some View {
        Section {
            LabeledContent {
                HStack(spacing: 10) {
                    grantLabel(viewModel.dictation.microphoneAccess == .authorized)
                    if viewModel.dictation.microphoneAccess != .authorized {
                        Button(viewModel.dictation.microphoneAccess == .denied ? "Open Settings" : "Allow") {
                            Task { await viewModel.dictation.requestMicrophoneAccess() }
                        }
                    }
                }
            } label: {
                settingLabel("Microphone", "Records your side")
            }

            LabeledContent {
                Button("Open System Settings") {
                    VoicePermissions.openScreenRecordingSettings()
                }
            } label: {
                settingLabel("Screen & System Audio Recording", "Records the other side")
            }
        } header: {
            Text("Permissions")
        } footer: {
            Text("Capturing what the Mac plays goes through ScreenCaptureKit, which is the only route that needs nothing installed and no rerouting of your output device. It asks for the screen permission because that is the framework it belongs to; Crest never reads a pixel and attaches no video output at all.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Summaries

    private func summarySection(_ viewModel: CrestViewModel) -> some View {
        @Bindable var viewModel = viewModel

        return Section {
            Toggle("Summarize as soon as a meeting ends", isOn: $viewModel.meetingAutoSummarize)

            if let reason = ModelCleanup.unavailableReason {
                Label(reason, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Summaries")
        } footer: {
            Text("Apple's on-device model reads the transcript in slices and merges the notes, because its context window is far shorter than a meeting. A long call takes a minute or two. Summaries are a starting point, not minutes — check anything that matters.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Storage

    private var storageSection: some View {
        let stats = viewModel.meetingStore.analytics

        return Section {
            LabeledContent("Stored") {
                Text("\(stats.count) meeting\(stats.count == 1 ? "" : "s"), \(ByteFormat.string(stats.bytes))")
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Recorded time", value: DurationText.string(stats.totalDuration))

            LabeledContent("Transcripts") {
                HStack(spacing: 10) {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([MeetingStore.directory])
                    }
                    Button("Delete all", role: .destructive) {
                        viewModel.meetingStore.deleteAll()
                    }
                    .disabled(stats.isEmpty)
                }
            }
        } header: {
            Text("Storage")
        } footer: {
            Text("Only the transcript is kept, never the audio: an hour of recorded call is orders of magnitude larger than the text of it, and Crest is not in the business of quietly filling your disk. Transcripts are plain JSON in Application Support and can be deleted from Finder at any time.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Bits

    private func settingLabel(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func grantLabel(_ isGranted: Bool) -> some View {
        Label(
            isGranted ? "Granted" : "Not granted",
            systemImage: isGranted ? "checkmark.circle.fill" : "xmark.circle"
        )
        .font(.caption)
        .foregroundStyle(isGranted ? .green : .orange)
    }
}
