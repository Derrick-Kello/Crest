//
//  MeetingsSectionView.swift
//  Crest
//

import SwiftUI

/// The Meetings tab: what your calls add up to, and the transcripts they left behind.
///
/// Deliberately a different shape from the Voice tab, because the two features answer
/// different questions. Dictation is about speed, so its figures are rates and its
/// headline is time saved. A meeting is about time spent and how it was shared, so this
/// leads with hours and a talk-share bar, and the list below is a filing cabinet rather
/// than a clipboard buffer.
///
/// Every figure here comes from the meeting index, so drawing this tab costs one small
/// file read no matter how many meetings are stored.
struct MeetingsSectionView: View {
    @Environment(CrestViewModel.self) private var viewModel

    var body: some View {
        PanelCard(section: .meetings) {
            if viewModel.meetings.state.isRecording {
                Text(DurationText.string(viewModel.meetings.elapsed))
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.red)
            } else if !viewModel.meetingStore.rows.isEmpty {
                Text(DurationText.string(viewModel.meetingStore.analytics.totalDuration))
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                if !viewModel.meetingsEnabled {
                    disabledState
                } else {
                    activeState
                }
            }
        }
    }

    private var disabledState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Records both sides of a call, transcribes them separately so you can tell who said what, and writes the summary on this Mac.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Needs the microphone, and Screen & System Audio Recording to hear the other side. No bot joins your call and nothing is uploaded.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Turn on meeting notes") {
                viewModel.meetingsEnabled = true
            }
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private var activeState: some View {
        recordButton

        if let warning = viewModel.meetings.systemAudioWarning, viewModel.meetings.state.isRecording {
            Label(warning, systemImage: "speaker.slash")
                .font(.system(size: 10))
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }

        if case .error(let message) = viewModel.meetings.state {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.system(size: 10))
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }

        if viewModel.meetings.state.isRecording, let meeting = viewModel.meetings.current {
            liveTranscript(meeting)
        }

        if !viewModel.meetingStore.rows.isEmpty {
            statistics
            Divider()
            transcripts
        }
    }

    // MARK: - Recording

    private var recordButton: some View {
        let isRecording = viewModel.meetings.state.isRecording
        let isSummarizing = viewModel.meetings.state.isSummarizing

        return Button {
            isRecording ? viewModel.stopMeeting() : viewModel.startMeeting()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: isRecording ? "stop.circle.fill" : "record.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(isRecording ? AnyShapeStyle(.red) : AnyShapeStyle(.tint))

                VStack(alignment: .leading, spacing: 1) {
                    Text(isRecording ? "Stop and summarize" : "Record this meeting")
                        .font(.system(size: 12, weight: .medium))
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if isRecording {
                    VoiceWaveform(
                        level: max(viewModel.meetings.micLevel, viewModel.meetings.systemLevel),
                        isActive: true,
                        barCount: 6
                    )
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
        .disabled(isSummarizing)
    }

    private var subtitle: String {
        if case .summarizing(let fraction) = viewModel.meetings.state {
            return "Writing the summary — \(Int(fraction * 100))%"
        }
        if viewModel.meetings.state.isRecording {
            return viewModel.meetings.current?.title ?? "Recording"
        }
        if let application = CallDetector.runningCallApplication() {
            return "\(application) is open"
        }
        return "Both sides, transcribed on-device"
    }

    /// The last thing each side said. Not the whole transcript: this is a reassurance
    /// that it is hearing both of you, which is the one thing you cannot verify
    /// afterwards.
    @ViewBuilder
    private func liveTranscript(_ meeting: Meeting) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(meeting.segments.suffix(2)) { segment in
                HStack(alignment: .top, spacing: 5) {
                    Image(systemName: segment.source.symbolName)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .frame(width: 12)
                        .padding(.top, 2)
                    Text(segment.text)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(7)
        .background(.quaternary.opacity(0.25), in: .rect(cornerRadius: 8))
    }

    // MARK: - Analytics

    private var statistics: some View {
        let stats = viewModel.meetingStore.analytics

        return VStack(alignment: .leading, spacing: 9) {
            PanelHeadlineFigure(
                symbolName: "clock",
                value: DurationText.string(stats.totalDuration) + " in meetings",
                caption: caption(stats)
            )

            if let share = stats.talkShare {
                TalkShareBar(yourShare: share)
            }

            Divider()

            PanelFigureRow(figures: [
                .init(value: "\(stats.count)", label: "recorded"),
                .init(value: DurationText.string(stats.averageDuration), label: "average"),
                .init(value: stats.words.formatted(.number.notation(.compactName)), label: "words"),
                .init(value: ByteFormat.string(stats.bytes), label: "on disk"),
            ])

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

    private func caption(_ stats: MeetingAnalytics) -> String {
        guard stats.countThisWeek > 0 else {
            return "\(stats.count) recorded · longest \(DurationText.string(stats.longest))"
        }
        return "\(DurationText.string(stats.durationThisWeek)) of it in the last 7 days, across \(stats.countThisWeek)"
    }

    private func footnote(_ stats: MeetingAnalytics) -> String? {
        var parts: [String] = []
        if stats.actionItems > 0 { parts.append("\(stats.actionItems) action items") }
        if stats.unsummarized > 0 { parts.append("\(stats.unsummarized) not summarized") }
        if let application = stats.topApplication, stats.topApplicationCount > 1 {
            parts.append("mostly \(application)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - Transcripts

    private var transcripts: some View {
        VStack(alignment: .leading, spacing: PanelMetrics.rowSpacing) {
            HStack {
                Text("Transcripts")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Open all") { viewModel.openMeetings() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            ForEach(viewModel.meetingStore.rows.prefix(4)) { row in
                TranscriptRow(row: row) { viewModel.openMeetings() }
            }

            if viewModel.meetingStore.rows.count > 4 {
                Text("and \(viewModel.meetingStore.rows.count - 4) more")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

/// Who did the talking, as one bar.
///
/// The figure nobody has without a transcript of both sides, and the reason the recorder
/// captures the microphone and the system output separately instead of mixing them.
private struct TalkShareBar: View {
    let yourShare: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text("You \(Int((yourShare * 100).rounded()))%")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tint)
                Spacer()
                Text("Others \(Int(((1 - yourShare) * 100).rounded()))%")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geometry in
                HStack(spacing: 1.5) {
                    Capsule()
                        .fill(.tint)
                        .frame(width: max(2, geometry.size.width * yourShare))
                    Capsule()
                        .fill(.quaternary)
                }
            }
            .frame(height: 5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("You spoke \(Int((yourShare * 100).rounded())) percent of the words")
    }
}

/// One stored transcript, with the information that makes it recognisable three weeks
/// later: when, where, how long, whether it was summarized, and what it costs on disk.
private struct TranscriptRow: View {
    let row: MeetingSummaryRow
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: row.isSummarized ? "sparkles" : "waveform")
                    .font(.system(size: 10))
                    .foregroundStyle(row.isSummarized ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                    .frame(width: 14)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(row.title)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(DurationText.string(row.duration))
                            .font(.system(size: 10))
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                    }

                    if let headline = row.headline {
                        Text(headline)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .multilineTextAlignment(.leading)
                    }

                    Text(detail)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("Open in Meeting Notes")
    }

    private var detail: String {
        var parts = [row.startedAt.formatted(date: .abbreviated, time: .shortened)]
        if let share = row.talkShare {
            parts.append("you \(Int((share * 100).rounded()))%")
        }
        if row.actionItemCount > 0 {
            parts.append("\(row.actionItemCount) action\(row.actionItemCount == 1 ? "" : "s")")
        }
        parts.append(ByteFormat.string(row.bytes))
        return parts.joined(separator: " · ")
    }
}
