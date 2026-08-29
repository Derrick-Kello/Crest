//
//  ClipboardService.swift
//  Crest
//

import AppKit
import Foundation
import OSLog

enum ClipboardKind: String, Codable, Sendable {
    case text, link, file, image

    var iconName: String {
        switch self {
        case .text: "text.alignleft"
        case .link: "link"
        case .file: "doc"
        case .image: "photo"
        }
    }
}

struct ClipboardEntry: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let kind: ClipboardKind
    /// Short single-line preview shown in lists. Never the full payload.
    let preview: String
    let copiedAt: Date
    var isPinned: Bool

    /// Full text for text/link/file entries. Images keep their bytes on disk and
    /// leave this nil, so a session of screenshot-copying doesn't sit in RAM.
    var text: String?
    var imageFileName: String?
    var byteCount: Int
}

/// Clipboard history: polls the pasteboard, keeps a bounded list, persists to disk.
///
/// Memory is the design constraint. Text is capped per entry and the history is
/// capped in count, while image payloads are written to disk immediately and only
/// referenced by filename — copying twenty screenshots costs twenty paths in RAM,
/// not twenty bitmaps.
@MainActor
@Observable
final class ClipboardService {
    static let shared = ClipboardService()

    private(set) var entries: [ClipboardEntry] = []
    var isEnabled: Bool {
        didSet {
            Preferences.clipboardEnabled = isEnabled
            isEnabled ? start() : stop()
        }
    }

    /// The most recent entries are what anyone actually reaches for; older ones are
    /// dropped so the file and the array both stay small.
    private let historyLimit = 150
    private let maxTextBytes = 256 * 1024

    private var pollTask: Task<Void, Never>?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private let logger = Logger(subsystem: "com.smarthive.crest", category: "Clipboard")

    private let storeURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Crest")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()

    private var historyFile: URL { storeURL.appending(path: "ClipboardHistory.json") }
    private var imagesDirectory: URL { storeURL.appending(path: "ClipboardImages") }

    private init() {
        isEnabled = Preferences.clipboardEnabled
        load()
        if isEnabled { start() }
    }

    // MARK: - Polling

    /// The pasteboard has no change notification, so polling is the only option.
    /// Once a second is frequent enough that a copy is in the list before the user
    /// can open the panel, and cheap enough to be invisible — `changeCount` is an
    /// integer read, and nothing else happens unless it moved.
    private func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                self.captureIfChanged()
            }
        }
    }

    private func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func captureIfChanged() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        // Password managers mark their pasteboard items as transient or concealed.
        // Recording those into a plaintext history file would be a genuine leak.
        let types = pasteboard.types ?? []
        let isConcealed = types.contains(NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
            || types.contains(NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
            || types.contains(NSPasteboard.PasteboardType("com.agilebits.onepassword"))
        guard !isConcealed else { return }

        guard let entry = makeEntry(from: pasteboard) else { return }
        insert(entry)
    }

    private func makeEntry(from pasteboard: NSPasteboard) -> ClipboardEntry? {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL], let url = urls.first {
            if url.isFileURL {
                return ClipboardEntry(
                    id: UUID(), kind: .file, preview: url.lastPathComponent,
                    copiedAt: .now, isPinned: false, text: url.path,
                    imageFileName: nil, byteCount: url.path.utf8.count
                )
            }
            return ClipboardEntry(
                id: UUID(), kind: .link, preview: url.absoluteString,
                copiedAt: .now, isPinned: false, text: url.absoluteString,
                imageFileName: nil, byteCount: url.absoluteString.utf8.count
            )
        }

        if let string = pasteboard.string(forType: .string) {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let stored = String(trimmed.prefix(maxTextBytes))
            return ClipboardEntry(
                id: UUID(), kind: .text, preview: Self.preview(of: stored),
                copiedAt: .now, isPinned: false, text: stored,
                imageFileName: nil, byteCount: stored.utf8.count
            )
        }

        if let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) {
            let name = "\(UUID().uuidString).png"
            do {
                try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
                let png = NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:]) ?? data
                try png.write(to: imagesDirectory.appending(path: name))
                let size = NSImage(data: data)?.size ?? .zero
                return ClipboardEntry(
                    id: UUID(), kind: .image,
                    preview: "Image \(Int(size.width))×\(Int(size.height))",
                    copiedAt: .now, isPinned: false, text: nil,
                    imageFileName: name, byteCount: png.count
                )
            } catch {
                logger.error("Could not store clipboard image: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
        return nil
    }

    private func insert(_ entry: ClipboardEntry) {
        // Re-copying the same thing should move it up, not create a duplicate.
        if let index = entries.firstIndex(where: { $0.text != nil && $0.text == entry.text }) {
            var existing = entries.remove(at: index)
            existing = ClipboardEntry(
                id: existing.id, kind: existing.kind, preview: existing.preview,
                copiedAt: .now, isPinned: existing.isPinned, text: existing.text,
                imageFileName: existing.imageFileName, byteCount: existing.byteCount
            )
            entries.insert(existing, at: 0)
        } else {
            entries.insert(entry, at: 0)
        }
        trim()
        save()
    }

    /// Pinned entries survive trimming — that is the entire point of pinning.
    private func trim() {
        guard entries.count > historyLimit else { return }
        var kept: [ClipboardEntry] = []
        var unpinnedBudget = historyLimit - entries.count(where: \.isPinned)
        for entry in entries {
            if entry.isPinned {
                kept.append(entry)
            } else if unpinnedBudget > 0 {
                kept.append(entry)
                unpinnedBudget -= 1
            } else if let name = entry.imageFileName {
                try? FileManager.default.removeItem(at: imagesDirectory.appending(path: name))
            }
        }
        entries = kept
    }

    // MARK: - Actions

    func copyToPasteboard(_ entry: ClipboardEntry) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        if let name = entry.imageFileName,
           let data = try? Data(contentsOf: imagesDirectory.appending(path: name)) {
            pasteboard.setData(data, forType: .png)
        } else if let text = entry.text {
            pasteboard.setString(text, forType: .string)
        }
        // Our own write bumps the change count; skip it so it isn't re-recorded.
        lastChangeCount = pasteboard.changeCount
    }

    func togglePin(_ entry: ClipboardEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index].isPinned.toggle()
        save()
    }

    func delete(_ entry: ClipboardEntry) {
        entries.removeAll { $0.id == entry.id }
        if let name = entry.imageFileName {
            try? FileManager.default.removeItem(at: imagesDirectory.appending(path: name))
        }
        save()
    }

    func clearAll() {
        // Pinned entries are explicitly kept: "clear" means clear the churn.
        let pinned = entries.filter(\.isPinned)
        for entry in entries where !entry.isPinned {
            if let name = entry.imageFileName {
                try? FileManager.default.removeItem(at: imagesDirectory.appending(path: name))
            }
        }
        entries = pinned
        save()
    }

    func image(for entry: ClipboardEntry) -> NSImage? {
        guard let name = entry.imageFileName else { return nil }
        return NSImage(contentsOf: imagesDirectory.appending(path: name))
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: historyFile),
              let decoded = try? JSONDecoder().decode([ClipboardEntry].self, from: data)
        else { return }
        entries = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: historyFile, options: .atomic)
    }

    private static func preview(of text: String) -> String {
        let line = text.split(separator: "\n").first.map(String.init) ?? text
        return String(line.prefix(120))
    }
}
