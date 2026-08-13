//
//  ClipboardSectionView.swift
//  DiskPilot
//

import SwiftUI

struct ClipboardSectionView: View {
    @Environment(DiskPilotViewModel.self) private var viewModel

    private var clipboard: ClipboardService { viewModel.clipboard }

    /// Pinned first, then most recent — the two reasons anything is in this list.
    private var ordered: [ClipboardEntry] {
        clipboard.entries.sorted {
            $0.isPinned != $1.isPinned ? $0.isPinned : $0.copiedAt > $1.copiedAt
        }
    }

    var body: some View {
        PanelCard(section: .clipboard) {
            if clipboard.isEnabled, !clipboard.entries.isEmpty {
                Text("\(clipboard.entries.count)")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        } content: {
            VStack(alignment: .leading, spacing: 6) {
                if !clipboard.isEnabled {
                    disabledState
                } else if clipboard.entries.isEmpty {
                    Text("Anything you copy shows up here. Nothing yet.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(ordered.prefix(6)) { entry in
                        row(entry)
                    }
                    footer
                }
            }
        }
    }

    private var disabledState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Clipboard history is off. Turn it on to keep the last 150 things you copied.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Turn on") { clipboard.isEnabled = true }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }

    private func row(_ entry: ClipboardEntry) -> some View {
        HStack(spacing: 7) {
            Image(systemName: entry.kind.iconName)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .frame(width: 13)

            Text(entry.preview)
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 4)

            if entry.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.orange)
            }

            Text(entry.copiedAt, style: .relative)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .contentShape(.rect)
        .onTapGesture {
            clipboard.copyToPasteboard(entry)
            viewModel.statusMessage = "Copied to clipboard"
        }
        .contextMenu {
            Button(entry.isPinned ? "Unpin" : "Pin") { clipboard.togglePin(entry) }
            Button("Delete", role: .destructive) { clipboard.delete(entry) }
        }
        .help("Click to copy")
    }

    private var footer: some View {
        HStack {
            if clipboard.entries.count > 6 {
                Text("\(clipboard.entries.count - 6) more")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button("Clear") { clipboard.clearAll() }
                .buttonStyle(.link)
                .font(.system(size: 10))
                .help("Removes everything except pinned items")
        }
    }
}
