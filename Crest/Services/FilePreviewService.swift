//
//  FilePreviewService.swift
//  Crest
//

import AppKit
import Foundation
import QuickLookThumbnailing

/// What the preview pane shows about one file.
struct FilePreview: Sendable, Equatable {
    var path: String
    var name: String
    var kind: String
    var size: UInt64?
    var modified: Date?
    var isDirectory: Bool
    /// Set for app bundles, which are the one kind of "file" where the version is
    /// the thing you actually wanted to know.
    var version: String?

    var displayPath: String {
        let home = NSHomeDirectory()
        let parent = (path as NSString).deletingLastPathComponent
        return parent.hasPrefix(home) ? "~" + parent.dropFirst(home.count) : parent
    }

    var formattedSize: String? {
        size.map { ByteFormat.string($0) }
    }
}

/// Reads file metadata and renders QuickLook thumbnails for the command bar.
///
/// Both halves are off the main actor and both are cached: the preview pane
/// redraws as the arrow keys move down the list, and re-reading the same file's
/// attributes — or re-rendering a thumbnail of a 40 MB PDF — once per keypress is
/// exactly the kind of work that makes a launcher feel slow.
@MainActor
final class FilePreviewService {
    static let shared = FilePreviewService()

    private var metadataCache: [String: FilePreview] = [:]
    private var thumbnailCache: [String: NSImage] = [:]

    private init() {}

    /// Metadata for `path`, read once and kept.
    ///
    /// Async rather than a cached getter that starts its own load: a getter called
    /// from a view body has to mutate bookkeeping while SwiftUI is rendering,
    /// which is the shape of bug that shows up later as a redraw loop.
    func preview(for path: String) async -> FilePreview {
        if let cached = metadataCache[path] { return cached }

        let preview = await Task.detached(priority: .userInitiated) {
            FilePreviewService.read(path)
        }.value

        // Bounded: the pane only ever shows one file, and a session that scrolled
        // past a thousand of them does not need them all kept.
        if metadataCache.count > 300 { metadataCache.removeAll() }
        metadataCache[path] = preview
        return preview
    }

    /// A QuickLook thumbnail, or nil when the file has no representation worth
    /// showing — a folder, a binary, anything QuickLook has no generator for.
    func thumbnail(for path: String) async -> NSImage? {
        if let cached = thumbnailCache[path] { return cached }

        let request = QLThumbnailGenerator.Request(
            fileAt: URL(fileURLWithPath: path),
            size: CGSize(width: 200, height: 150),
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            // `.thumbnail` only: the low-quality tiers are the file's own icon,
            // which the pane already draws while waiting. Asking for those means
            // replacing an icon with the same icon and a redraw for nothing.
            representationTypes: .thumbnail
        )

        let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
        guard let representation else { return nil }

        let image = NSImage(cgImage: representation.cgImage, size: representation.contentRect.size)
        if thumbnailCache.count > 120 { thumbnailCache.removeAll() }
        thumbnailCache[path] = image
        return image
    }

    /// The icon is always available immediately and is never wrong, just less
    /// interesting than a thumbnail — so it fills the space until one arrives.
    func icon(for path: String) -> NSImage {
        CommandBarService.shared.icon(forApp: path)
    }

    // MARK: - Reading

    nonisolated private static func read(_ path: String) -> FilePreview {
        let url = URL(fileURLWithPath: path)
        let values = try? url.resourceValues(forKeys: [
            .localizedTypeDescriptionKey, .totalFileAllocatedSizeKey, .fileSizeKey,
            .contentModificationDateKey, .isDirectoryKey, .isPackageKey,
        ])

        let isDirectory = values?.isDirectory == true && values?.isPackage != true
        var size = values?.totalFileAllocatedSize.map(UInt64.init) ?? values?.fileSize.map(UInt64.init)
        // A folder reports a few kilobytes of directory entry, which is never the
        // number anyone means by "how big is this folder".
        if isDirectory { size = nil }

        return FilePreview(
            path: path,
            name: url.lastPathComponent,
            kind: values?.localizedTypeDescription ?? (isDirectory ? "Folder" : "Document"),
            size: size,
            modified: values?.contentModificationDate,
            isDirectory: isDirectory,
            version: url.pathExtension == "app" ? bundleVersion(at: url) : nil
        )
    }

    nonisolated private static func bundleVersion(at url: URL) -> String? {
        let plist = url.appending(path: "Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let raw = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dictionary = raw as? [String: Any]
        else { return nil }
        return (dictionary["CFBundleShortVersionString"] as? String)
            ?? (dictionary["CFBundleVersion"] as? String)
    }
}
