//
//  CommandBarView.swift
//  Crest
//

import AppKit
import SwiftUI

/// One row of the result list, either a section header or a result.
///
/// Flattening the grouped results into a single array is what lets the arrow keys
/// stay simple: the selection is an index into `rows`, headers are skipped when
/// moving, and the list needs no nested `ForEach` to keep in sync.
private enum CommandRow: Identifiable {
    case header(String)
    case entry(CommandEntry)

    var id: String {
        switch self {
        case .header(let title): "header:" + title
        case .entry(let entry): entry.id
        }
    }

    var entry: CommandEntry? {
        if case .entry(let entry) = self { return entry }
        return nil
    }
}

struct CommandBarView: View {
    let onExecute: (CommandEntry) -> Void
    let onDismiss: () -> Void
    /// Reports the whole panel size, not just its height: the bar widens when the
    /// preview pane appears and has to narrow again when it goes.
    let onSizeChange: (CGSize) -> Void

    @State private var query = ""
    @State private var rows: [CommandRow] = []
    @State private var selection = 0

    private let rowHeight: CGFloat = 42
    private let headerHeight: CGFloat = 26
    private let fieldHeight: CGFloat = 58
    /// Roughly eight result rows. Past that the list is a scroll, not a glance.
    private let maximumListHeight: CGFloat = 360
    /// Tall enough for a thumbnail and its details, so the preview does not
    /// arrive squashed into two rows' worth of space on a short result list.
    private let minimumPreviewHeight: CGFloat = 300

    /// The bar's width with no preview beside it.
    static let baseWidth: CGFloat = 640

    var body: some View {
        VStack(spacing: 0) {
            field

            if !rows.isEmpty {
                seam
                HStack(spacing: 0) {
                    list
                    if let path = previewPath {
                        verticalSeam
                        FilePreviewPane(path: path, fallbackTitle: rows[selection].entry?.title ?? "")
                            .frame(height: listHeight)
                    }
                }
            } else if !query.isEmpty {
                empty
            }
        }
        .commandBarSurface()
        .onAppear { refresh() }
        .onChange(of: query) { _, _ in refresh() }
        // The catalog is built in the background, so results are recomputed when
        // it lands — otherwise the first search after a cold launch shows nothing
        // until another character is typed.
        .onChange(of: CommandBarService.shared.indexGeneration) { _, _ in refresh() }
        // Spotlight answers on its own schedule; folding its results in when they
        // arrive is what makes file search feel like part of the same list.
        .onChange(of: FileSearchService.shared.generation) { _, _ in refresh() }
        // Aliases are edited in Settings while the bar can be open behind it.
        .onChange(of: AliasStore.shared.generation) { _, _ in refresh() }
        // Moving the selection on and off a file changes whether the preview pane
        // is there at all, which changes how wide the panel has to be.
        .onChange(of: selection) { _, _ in reportSize() }
    }

    /// The file the preview pane is showing, or nil when the selection is not
    /// something with a file behind it.
    ///
    /// Applications count: seeing the version and where a bundle actually lives is
    /// how you tell two copies of Xcode apart before launching the wrong one.
    private var previewPath: String? {
        guard Preferences.filePreviewEnabled,
              rows.indices.contains(selection),
              let entry = rows[selection].entry,
              entry.category == .file || entry.category == .application
        else { return nil }
        return entry.item.filePath
    }

    // MARK: - Field

    private var field: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)

            CommandField(
                text: $query,
                placeholder: "Search apps, settings, tools and files…",
                onMove: { move(by: $0) },
                onSubmit: executeSelection,
                onCancel: onDismiss,
                onReveal: revealSelection,
                onCopyPath: copySelectedPath
            )

            if CommandBarService.shared.isIndexing {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
            }
        }
        .padding(.horizontal, 17)
        .frame(height: fieldHeight)
    }

    /// A hairline rule instead of `Divider`.
    ///
    /// `Divider` draws a separator colour meant for an opaque window, and over the
    /// glass it is either invisible or a hard grey bar depending on what is behind
    /// the bar. A wash of the foreground colour follows the appearance instead, and
    /// stays a hairline in both.
    private var seam: some View {
        Rectangle().fill(.primary.opacity(0.08)).frame(height: 1)
    }

    private var verticalSeam: some View {
        Rectangle().fill(.primary.opacity(0.08)).frame(width: 1)
    }

    private var empty: some View {
        VStack(spacing: 0) {
            seam
            HStack {
                Text("No results")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 17)
            .frame(height: rowHeight)
        }
    }

    // MARK: - List

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // A plain `VStack`, deliberately not `LazyVStack`. Inside this
                // panel the lazy container built its children once and never
                // rebuilt them: the rows stayed on the empty-query list while the
                // rest of the view updated around them — verified with a probe
                // label beside the list showing the correct new row count against
                // a list still drawing the old rows. The result set is capped at
                // fourteen, so there is nothing for laziness to save here anyway.
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        switch row {
                        case .header(let title):
                            header(title).id(index)
                        case .entry(let entry):
                            self.row(entry, isSelected: index == selection)
                                .id(index)
                                .contentShape(.rect)
                                .onTapGesture {
                                    selection = index
                                    executeSelection()
                                }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: listHeight)
            .onChange(of: selection) { _, new in
                withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(new, anchor: .center) }
            }
        }
    }

    private func header(_ title: String) -> some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .tracking(0.6)
            Spacer()
        }
        .padding(.horizontal, 17)
        .frame(height: headerHeight, alignment: .bottom)
        .padding(.bottom, 3)
    }

    private func row(_ entry: CommandEntry, isSelected: Bool) -> some View {
        HStack(spacing: 11) {
            icon(for: entry)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title)
                    .font(.system(size: 13.5, weight: entry.category == .answer ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(entry.subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            if isSelected {
                Text(actionHint(for: entry))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.leading, 5)
        .frame(height: rowHeight)
        .background {
            if isSelected {
                CommandBarSelection()
                    .padding(.horizontal, 8)
            }
        }
    }

    /// Says what ↩ will actually do, so nothing destructive happens unannounced.
    private func actionHint(for entry: CommandEntry) -> String {
        switch entry.action {
        case .launchApp, .openFile: "Open ↩"
        case .revealInFinder: "Reveal ↩"
        case .openURL: "Open ↩"
        case .copyText: "Copy ↩"
        case .shell, .appleScript: "Run ↩"
        case .appAction: "Go ↩"
        }
    }

    @ViewBuilder
    private func icon(for entry: CommandEntry) -> some View {
        if let path = entry.iconPath {
            Image(nsImage: CommandBarService.shared.icon(forApp: path))
                .resizable()
                .frame(width: 22, height: 22)
        } else {
            Image(systemName: entry.symbolName)
                .font(.system(size: 14))
                .frame(width: 22, height: 22)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Behaviour

    private var listHeight: CGFloat {
        let total = rows.reduce(into: CGFloat.zero) { height, row in
            height += row.entry == nil ? headerHeight + 3 : rowHeight
        }
        let floor = previewPath == nil ? 0 : minimumPreviewHeight
        return min(max(total + 6, floor), maximumListHeight)
    }

    private func reportSize() {
        let body: CGFloat
        if !rows.isEmpty {
            body = listHeight + 1
        } else if !query.isEmpty {
            body = rowHeight + 1
        } else {
            body = 0
        }
        let width = previewPath == nil
            ? Self.baseWidth
            : Self.baseWidth + FilePreviewPane.width + 1
        onSizeChange(CGSize(width: width, height: fieldHeight + body))
    }

    /// Rebuilds the flattened rows from the current query.
    ///
    /// Grouping happens here rather than in the service so the service stays a
    /// pure ranker: it returns the best results in order, and the view decides how
    /// to present them. Sections appear in the order their best result ranked, so
    /// whatever the user most likely meant is still the first thing on screen.
    private func refresh() {
        let results = CommandBarService.shared.results(for: query)

        var order: [CommandCategory] = []
        var grouped: [CommandCategory: [CommandEntry]] = [:]
        for entry in results {
            if grouped[entry.category] == nil { order.append(entry.category) }
            grouped[entry.category, default: []].append(entry)
        }

        var built: [CommandRow] = []
        for category in order {
            guard let entries = grouped[category] else { continue }
            // A single calculator answer needs no "Result" banner over it.
            if !(category == .answer && results.count == 1) {
                built.append(.header(category.title))
            }
            built.append(contentsOf: entries.map(CommandRow.entry))
        }

        rows = built
        selection = built.firstIndex(where: { $0.entry != nil }) ?? 0
        reportSize()
    }

    /// Moves the selection, stepping over section headers in either direction and
    /// wrapping at both ends so holding an arrow key never sticks.
    private func move(by delta: Int) {
        let selectable = rows.indices.filter { rows[$0].entry != nil }
        guard !selectable.isEmpty else { return }

        let current = selectable.firstIndex(of: selection) ?? 0
        let next = (current + delta + selectable.count) % selectable.count
        selection = selectable[next]
    }

    private func executeSelection() {
        guard rows.indices.contains(selection), let entry = rows[selection].entry else { return }
        onExecute(entry)
        query = ""
    }

    /// ⌘↩ on anything with a file behind it. Reaching a file's folder is the other
    /// half of finding it, and opening it first to get there is a detour.
    private func revealSelection() {
        guard rows.indices.contains(selection),
              let entry = rows[selection].entry,
              let path = entry.item.filePath
        else { return }
        onExecute(CommandEntry(
            item: CatalogItem(
                id: entry.id,
                title: entry.title,
                subtitle: entry.subtitle,
                category: entry.category,
                iconPath: entry.iconPath,
                keys: [],
                action: .revealInFinder(path: path)
            ),
            score: entry.score
        ))
        query = ""
    }

    /// ⌘⇧C, rather than ⌘C: plain ⌘C has to keep copying selected text out of the
    /// search field, which is what it does in every other field on the Mac.
    private func copySelectedPath() {
        guard rows.indices.contains(selection),
              let entry = rows[selection].entry,
              let path = entry.item.filePath
        else { return }
        onExecute(CommandEntry(
            item: CatalogItem(
                id: entry.id,
                title: entry.title,
                subtitle: entry.subtitle,
                category: entry.category,
                keys: [],
                action: .copyText(path)
            ),
            score: entry.score
        ))
        query = ""
    }
}
