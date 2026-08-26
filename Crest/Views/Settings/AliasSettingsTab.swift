//
//  AliasSettingsTab.swift
//  Crest
//

import SwiftUI

/// The names the user has taught the command bar.
///
/// Editing is held in a draft until the field is committed. Writing straight
/// through on every keystroke looked simpler and behaved badly: an alias is moved
/// off whatever else owned it when it is assigned, so typing "db" one letter at a
/// time would first steal "d" from something else on the way past.
struct AliasSettingsTab: View {
    private let store = AliasStore.shared

    @State private var picking = false
    /// Identifier → text being typed. Also holds rows added but not yet given an
    /// alias, which is what lets a new row exist before it has anything to store.
    @State private var drafts: [String: String] = [:]
    @State private var names: [String: String] = [:]
    @FocusState private var focused: String?

    var body: some View {
        Form {
            Section {
                if rows.isEmpty {
                    Text("No aliases yet. Add one so typing “t” opens Terminal, or “db” opens your database client.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(rows) { entry in
                        row(entry)
                    }
                }

                Button {
                    picking = true
                } label: {
                    Label("Add an alias", systemImage: "plus")
                }
                .buttonStyle(.link)
            } header: {
                Text("Aliases")
            } footer: {
                Text("Separate several with commas. An alias is matched whole, so even a single letter lands on exactly what you assigned it to instead of everything that contains it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
        // Committing on focus change is what makes clicking away behave the same
        // as pressing Return, which is what people expect of a field in a list.
        .onChange(of: focused) { previous, _ in
            if let previous { commit(previous) }
        }
        .sheet(isPresented: $picking) {
            CatalogPicker(
                title: "Pick something to alias",
                categories: [.application, .tool, .setting, .command]
            ) { item in
                picking = false
                names[item.id] = item.title
                drafts[item.id] = store.aliasList(for: item.id).joined(separator: ", ")
                focused = item.id
            }
        }
    }

    // MARK: - Rows

    /// Stored aliases, plus any row added in this session that has not been given
    /// one yet, sorted together so a new row does not jump position on commit.
    private var rows: [AliasEntry] {
        var entries = store.entries { identifier in names[identifier] ?? catalogTitle(for: identifier) }
        let existing = Set(entries.map(\.identifier))
        for identifier in drafts.keys where !existing.contains(identifier) {
            entries.append(AliasEntry(
                identifier: identifier,
                title: names[identifier] ?? catalogTitle(for: identifier) ?? identifier,
                aliases: []
            ))
        }
        return entries.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private func row(_ entry: AliasEntry) -> some View {
        HStack(spacing: 9) {
            icon(for: entry.identifier)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title)
                    .font(.system(size: 12.5))
                    .lineLimit(1)
                Text(previewLine(for: entry))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            // `labelsHidden`, or the Form hoists the placeholder out of the field
            // and every row grows a left-hand label reading "alias".
            TextField("alias", text: binding(for: entry))
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .font(.system(size: 12))
                .frame(width: 150)
                .focused($focused, equals: entry.identifier)
                .onSubmit { commit(entry.identifier) }

            Button {
                if focused == entry.identifier { focused = nil }
                drafts.removeValue(forKey: entry.identifier)
                store.remove(entry.identifier)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Remove these aliases")
            .accessibilityLabel("Remove the aliases for \(entry.title)")
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func icon(for identifier: String) -> some View {
        if identifier.hasPrefix("app:") {
            Image(nsImage: CommandBarService.shared.icon(forApp: String(identifier.dropFirst(4))))
                .resizable()
                .frame(width: 18, height: 18)
        } else {
            Image(systemName: symbol(for: identifier))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private func previewLine(for entry: AliasEntry) -> String {
        entry.aliases.isEmpty
            ? "Type an alias in the field to the right"
            : "Type " + entry.aliases.map { "“\($0)”" }.joined(separator: " or ") + " in the command bar"
    }

    // MARK: - Editing

    private func binding(for entry: AliasEntry) -> Binding<String> {
        Binding(
            get: { drafts[entry.identifier] ?? entry.joined },
            set: { drafts[entry.identifier] = $0 }
        )
    }

    private func commit(_ identifier: String) {
        guard let text = drafts[identifier] else { return }
        store.setAliases(text, for: identifier)
        // An alias that came out empty leaves no stored row, so the draft has to
        // stay or the row the user just added would vanish under their cursor.
        if !AliasStore.parse(text).isEmpty {
            drafts.removeValue(forKey: identifier)
        }
    }

    private func catalogTitle(for identifier: String) -> String? {
        CommandBarService.shared.items.first { $0.id == identifier }?.title
    }

    private func symbol(for identifier: String) -> String {
        CommandBarService.shared.items.first { $0.id == identifier }
            .map { $0.symbolName ?? $0.category.symbolName } ?? "questionmark.square.dashed"
    }
}
