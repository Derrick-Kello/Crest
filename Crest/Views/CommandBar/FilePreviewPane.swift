//
//  FilePreviewPane.swift
//  Crest
//

import SwiftUI

/// The pane beside the results, showing what the selected file actually is.
///
/// A file search that returns twelve rows called "notes.md" is a list of guesses
/// until you can see one. The thumbnail and the path together are what turn the
/// list into an answer, which is the whole reason to preview in the bar rather
/// than open the file to find out.
struct FilePreviewPane: View {
    let path: String
    let fallbackTitle: String

    private let service = FilePreviewService.shared

    @State private var preview: FilePreview?
    @State private var thumbnail: NSImage?

    var body: some View {
        VStack(spacing: 10) {
            artwork
                .frame(height: 116)
                .frame(maxWidth: .infinity)
                .background(.quaternary.opacity(0.25), in: .rect(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 3) {
                Text(preview?.name ?? fallbackTitle)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let preview {
                    detail("Kind", preview.kind)
                    if let version = preview.version { detail("Version", version) }
                    if let size = preview.formattedSize { detail("Size", size) }
                    if let modified = preview.modified {
                        detail("Modified", modified.formatted(date: .abbreviated, time: .shortened))
                    }
                    detail("Where", preview.displayPath)
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 3) {
                shortcut("↩", "Open")
                shortcut("⌘↩", "Reveal in Finder")
                shortcut("⌘⇧C", "Copy path")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(width: FilePreviewPane.width)
        // Keyed on the path, so moving the selection cancels the load for the row
        // that is no longer showing rather than racing it against the new one.
        .task(id: path) {
            preview = nil
            thumbnail = nil
            preview = await service.preview(for: path)
            thumbnail = await service.thumbnail(for: path)
        }
    }

    static let width: CGFloat = 208

    @ViewBuilder
    private var artwork: some View {
        if let image = thumbnail {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding(6)
        } else {
            Image(nsImage: service.icon(for: path))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 56, height: 56)
        }
    }

    private func detail(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .frame(width: 48, alignment: .leading)
            Text(value)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
    }

    private func shortcut(_ keys: String, _ label: String) -> some View {
        HStack(spacing: 6) {
            Text(keys)
                .font(.system(size: 9.5, weight: .medium))
                .padding(.horizontal, 4)
                .padding(.vertical, 1.5)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 4))
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }
}
