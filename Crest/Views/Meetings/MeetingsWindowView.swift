//
//  MeetingsWindowView.swift
//  Crest
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Meeting transcripts and their summaries.
///
/// A split view because the two halves answer different questions: the list is "which
/// meeting", the detail is "what happened in it". Loading is deliberately lazy — the list
/// is built from a small index file, and a transcript is only decoded when its row is
/// selected, so opening this window costs the same whether there are three meetings in it
/// or three hundred.
struct MeetingsWindowView: View {
    @Environment(CrestViewModel.self) private var viewModel

    @State private var selection: UUID?
    @State private var meeting: Meeting?
    @State private var isRenaming = false
    @State private var draftTitle = ""

    var body: some View {
        NavigationSplitView {
            list
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 340)
        } detail: {
            detail
        }
        .frame(minWidth: 720, minHeight: 480)
        .onChange(of: selection) { _, id in
            meeting = id.flatMap { viewModel.meetingStore.meeting(id: $0) }
        }
        // The recorder saves through the store, so a summary that finishes while this
        // window is open has to be picked back up rather than leaving the detail showing
        // the version from before it ran.
        .onChange(of: viewModel.meetingStore.rows) { _, _ in
            if let id = selection { meeting = viewModel.meetingStore.meeting(id: id) }
        }
        .onAppear {
            if selection == nil { selection = viewModel.meetingStore.rows.first?.id }
        }
    }

    // MARK: - List

    private var list: some View {
        List(viewModel.meetingStore.rows, selection: $selection) { row in
            VStack(alignment: .leading, spacing: 3) {
                Text(row.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                if let headline = row.headline {
                    Text(headline)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 5) {
                    Text(row.startedAt.formatted(date: .abbreviated, time: .shortened))
                    Text("·")
                    Text(DurationText.string(row.duration))
                    if row.actionItemCount > 0 {
                        Text("·")
                        Label("\(row.actionItemCount)", systemImage: "checkmark.circle")
                            .labelStyle(.titleAndIcon)
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 3)
            .tag(row.id)
            .contextMenu {
                Button("Rename…") {
                    draftTitle = row.title
                    selection = row.id
                    isRenaming = true
                }
                Button("Delete", role: .destructive) {
                    viewModel.meetingStore.delete(id: row.id)
                    if selection == row.id { selection = viewModel.meetingStore.rows.first?.id }
                }
            }
        }
        .overlay {
            if viewModel.meetingStore.rows.isEmpty {
                ContentUnavailableView(
                    "No meetings yet",
                    systemImage: "text.bubble",
                    description: Text("Recorded meetings and their summaries land here.")
                )
            }
        }
        .alert("Rename meeting", isPresented: $isRenaming) {
            TextField("Title", text: $draftTitle)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                guard let id = selection else { return }
                viewModel.meetingStore.rename(id: id, to: draftTitle)
                meeting = viewModel.meetingStore.meeting(id: id)
            }
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let meeting {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header(meeting)
                    summarySection(meeting)
                    transcriptSection(meeting)
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(meeting.title)
            .toolbar { toolbar(meeting) }
        } else {
            ContentUnavailableView(
                "Select a meeting",
                systemImage: "sidebar.left",
                description: Text("Pick one on the left to read its summary and transcript.")
            )
        }
    }

    private func header(_ meeting: Meeting) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(meeting.title)
                .font(.system(size: 19, weight: .semibold))

            HStack(spacing: 6) {
                Text(meeting.startedAt.formatted(date: .complete, time: .shortened))
                if let application = meeting.applicationName {
                    Text("·")
                    Text(application)
                }
                Text("·")
                Text(DurationText.string(meeting.duration))
                Text("·")
                Text("\(meeting.wordCount) words")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func summarySection(_ meeting: Meeting) -> some View {
        if let summary = meeting.summary {
            VStack(alignment: .leading, spacing: 14) {
                Text(summary.headline)
                    .font(.system(size: 14, weight: .semibold))

                Text(summary.overview)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                bulletList("Key points", symbol: "list.bullet", items: summary.keyPoints)
                bulletList("Decisions", symbol: "checkmark.seal", items: summary.decisions)

                if !summary.actionItems.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        sectionTitle("Action items", symbol: "checklist")
                        ForEach(summary.actionItems) { item in
                            HStack(alignment: .firstTextBaseline, spacing: 7) {
                                Image(systemName: "square")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                                Text(item.task)
                                    .font(.system(size: 12))
                                Text(item.owner)
                                    .font(.system(size: 10, weight: .medium))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.quaternary.opacity(0.5), in: .capsule)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }

                bulletList("Open questions", symbol: "questionmark.circle", items: summary.openQuestions)

                Text("Written on this Mac by Apple's on-device model. Check anything that matters.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.28), in: .rect(cornerRadius: 12))
            .textSelection(.enabled)
        } else if viewModel.meetings.state.isSummarizing {
            summarizingPlaceholder
        } else {
            noSummaryPlaceholder(meeting)
        }
    }

    private var summarizingPlaceholder: some View {
        let fraction: Double = if case .summarizing(let value) = viewModel.meetings.state { value } else { 0 }

        return VStack(alignment: .leading, spacing: 8) {
            Label("Writing the summary", systemImage: "sparkles")
                .font(.system(size: 12, weight: .medium))
            ProgressView(value: fraction)
                .progressViewStyle(.linear)
            Text("The transcript is read in slices and merged, because the on-device model's context window is far shorter than a meeting.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.28), in: .rect(cornerRadius: 12))
    }

    private func noSummaryPlaceholder(_ meeting: Meeting) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("No summary yet")
                    .font(.system(size: 12, weight: .medium))
                Text(ModelCleanup.isAvailable
                     ? "Runs on this Mac. Nothing is uploaded."
                     : ModelCleanup.unavailableReason ?? "")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Summarize") { viewModel.meetings.summarize(id: meeting.id) }
                .disabled(!ModelCleanup.isAvailable || viewModel.meetings.state.isSummarizing)
        }
        .padding(16)
        .background(.quaternary.opacity(0.28), in: .rect(cornerRadius: 12))
    }

    private func transcriptSection(_ meeting: Meeting) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Transcript", symbol: "text.alignleft")

            ForEach(meeting.segments) { segment in
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(Meeting.timestamp(segment.offset))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                        Image(systemName: segment.source.symbolName)
                            .font(.system(size: 9))
                            .foregroundStyle(segment.source == .microphone ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    }
                    .frame(width: 44, alignment: .trailing)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(segment.source.speakerLabel)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(segment.source == .microphone ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        Text(segment.text)
                            .font(.system(size: 12))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .textSelection(.enabled)
    }

    private func bulletList(_ title: String, symbol: String, items: [String]) -> some View {
        Group {
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    sectionTitle(title, symbol: symbol)
                    ForEach(items, id: \.self) { item in
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            Text("•").foregroundStyle(.tertiary)
                            Text(item).font(.system(size: 12))
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
    }

    private func sectionTitle(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private func toolbar(_ meeting: Meeting) -> some ToolbarContent {
        ToolbarItemGroup {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(meeting.markdown(), forType: .string)
                viewModel.statusMessage = "Copied the meeting as Markdown"
            } label: {
                Label("Copy as Markdown", systemImage: "doc.on.doc")
            }
            .help("Copy the summary and transcript as Markdown")

            Button {
                export(meeting)
            } label: {
                Label("Save…", systemImage: "square.and.arrow.down")
            }
            .help("Save as a Markdown file")

            Button {
                viewModel.meetings.summarize(id: meeting.id)
            } label: {
                Label(meeting.summary == nil ? "Summarize" : "Redo summary", systemImage: "sparkles")
            }
            .disabled(!ModelCleanup.isAvailable || viewModel.meetings.state.isSummarizing)
            .help("Write the summary on this Mac")
        }
    }

    private func export(_ meeting: Meeting) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = meeting.title
            .replacingOccurrences(of: "/", with: "-") + ".md"
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? meeting.markdown().write(to: url, atomically: true, encoding: .utf8)
    }
}
