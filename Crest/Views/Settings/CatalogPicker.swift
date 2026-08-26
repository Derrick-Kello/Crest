//
//  CatalogPicker.swift
//  Crest
//

import SwiftUI

/// A searchable list of everything the command bar knows about, for the settings
/// screens that need the user to point at one thing.
///
/// Reuses the command bar's own index and matcher rather than listing
/// `/Applications` again: an app findable by typing "vscode" in the bar should be
/// findable the same way when assigning it a shortcut, and there is no second
/// notion of what counts as installed to keep in sync.
struct CatalogPicker: View {
    let title: String
    /// Which parts of the catalog to offer. Files and clipboard rows are never
    /// included — neither survives long enough to be worth binding to.
    let categories: Set<CommandCategory>
    /// The caller dismisses. Picking often means replacing this sheet with the
    /// next step, and calling `dismiss()` here first clears the presentation
    /// binding the caller just set — which read as the picker doing nothing.
    let onPick: (CatalogItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(14)

            Divider()

            TextField("Search", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                // Type a name, press Return, done — without reaching for the
                // mouse to click the one row the search has left.
                .onSubmit { if let first = matches.first { onPick(first) } }

            Divider()

            if matches.isEmpty {
                Spacer()
                Text(CommandBarService.shared.isIndexing ? "Building the index…" : "Nothing matches")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(matches) { item in
                    // A `Button`, not a tap gesture on the row.
                    // Inside a `List`, the first click on a row goes to the list
                    // itself and the gesture never sees it, so picking anything
                    // took two clicks — which reads as the first one not working.
                    Button {
                        onPick(item)
                    } label: {
                        row(item)
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.inset)
            }
        }
        .frame(width: 420, height: 440)
        .onAppear { CommandBarService.shared.buildIndex() }
    }

    private func row(_ item: CatalogItem) -> some View {
        HStack(spacing: 9) {
            if let path = item.iconPath {
                Image(nsImage: CommandBarService.shared.icon(forApp: path))
                    .resizable()
                    .frame(width: 18, height: 18)
            } else {
                Image(systemName: item.symbolName ?? item.category.symbolName)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.system(size: 12.5))
                Text(item.subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.vertical, 2)
        .contentShape(.rect)
    }

    /// Sorted by the same fuzzy score the command bar uses, so the first row is
    /// the one the bar would have put first for the same query.
    private var matches: [CatalogItem] {
        let pool = CommandBarService.shared.items.filter { categories.contains($0.category) }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return Array(pool.prefix(200)) }

        let tokens = FuzzyMatch.tokenize(trimmed)
        let joined = tokens.joined()
        return pool
            .compactMap { item -> (CatalogItem, Int)? in
                guard let score = FuzzyMatch.score(tokens: tokens, joined: joined, keys: item.keys) else {
                    return nil
                }
                return (item, score)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(60)
            .map(\.0)
    }
}
