//
//  HotKeysSettingsTab.swift
//  Crest
//

import SwiftUI

/// Global shortcuts: the one that opens the command bar, plus whatever the user
/// has bound to individual apps and Crest actions.
struct HotKeysSettingsTab: View {
    @Environment(CrestViewModel.self) private var viewModel

    private let service = UserHotKeyService.shared

    /// One sheet at a time, driven by a single piece of state. Two `.sheet`
    /// modifiers on one view raced when the picker dismissed itself and the
    /// recorder tried to appear in the same pass: the second sheet was swallowed
    /// and the Add button looked like it did nothing every other press.
    private enum Sheet: Identifiable {
        case picker
        case assign(CatalogItem)

        var id: String {
            switch self {
            case .picker: "picker"
            case .assign(let item): "assign:" + item.id
            }
        }
    }

    @State private var sheet: Sheet?
    @State private var pendingCombo: HotKeyCombo?

    var body: some View {
        @Bindable var viewModel = viewModel

        Form {
            // A signpost, not a control. The command bar has its own pane now, and
            // leaving a second copy of its shortcut here would give two fields
            // editing one setting — but somebody who came looking for it in
            // Shortcuts still has to be told where it went.
            Section {
                LabeledContent("Open command bar") {
                    Text(viewModel.commandBarEnabled ? viewModel.commandBarHotKey.displayString : "Off")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Text("The command bar has its own pane in the sidebar, where you can change this key and what it searches.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Command bar")
            }

            Section {
                if service.hotKeys.isEmpty {
                    Text("No shortcuts yet. Add one to jump straight to an app from anywhere.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(service.hotKeys) { hotKey in
                        row(hotKey)
                    }
                }

                Button {
                    pendingCombo = nil
                    sheet = .picker
                } label: {
                    Label("Add a shortcut", systemImage: "plus")
                }
                .buttonStyle(.link)
            } header: {
                Text("App and action shortcuts")
            } footer: {
                Text("Pressing the shortcut opens the app, or hides it when it is already in front. Shortcuts need at least one of ⌘, ⌥ or ⌃.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
        .sheet(item: $sheet) { current in
            switch current {
            case .picker:
                // Applications and Crest's own actions only: a settings pane
                // is one keystroke away in the command bar, and a global key for
                // each of two hundred of them is not what this list is for.
                CatalogPicker(
                    title: "Pick an app or action",
                    categories: [.application, .tool]
                ) { item in
                    pendingCombo = nil
                    sheet = .assign(item)
                }
            case .assign(let item):
                assignSheet(for: item)
            }
        }
    }

    // MARK: - Rows

    private func row(_ hotKey: UserHotKey) -> some View {
        HStack(spacing: 9) {
            icon(for: hotKey)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(hotKey.name)
                    .font(.system(size: 12.5))
                    .lineLimit(1)
                if service.failedIdentifiers.contains(hotKey.id) {
                    Text("Another app already owns this shortcut")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.orange)
                }
            }

            Spacer(minLength: 8)

            ShortcutRecorder(
                combo: Binding(
                    get: { hotKey.combo },
                    set: { newValue in
                        guard let newValue else {
                            service.remove(hotKey)
                            return
                        }
                        service.assign(newValue, to: hotKey.target, name: hotKey.name, symbolName: hotKey.symbolName)
                    }
                ),
                conflict: { service.conflict(for: $0, excluding: hotKey.target) }
            )
            .frame(width: 130, height: 22)
            .disabled(!hotKey.isEnabled)

            Toggle("", isOn: Binding(
                get: { hotKey.isEnabled },
                set: { service.setEnabled($0, for: hotKey) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .help(hotKey.isEnabled ? "Turn this shortcut off" : "Turn this shortcut on")

            Button {
                service.remove(hotKey)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Remove this shortcut")
            .accessibilityLabel("Remove the shortcut for \(hotKey.name)")
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func icon(for hotKey: UserHotKey) -> some View {
        if let path = hotKey.appPath {
            Image(nsImage: CommandBarService.shared.icon(forApp: path))
                .resizable()
                .frame(width: 18, height: 18)
        } else {
            Image(systemName: hotKey.symbolName ?? "wrench.and.screwdriver")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Assignment

    private func assignSheet(for item: CatalogItem) -> some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Text("Shortcut for \(item.title)")
                    .font(.headline)
                Text("Press the keys you want to use. It has to include ⌘, ⌥ or ⌃.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            ShortcutRecorder(
                combo: $pendingCombo,
                conflict: { service.conflict(for: $0, excluding: target(for: item)) },
                placeholder: "Click, then press keys"
            )
            .frame(width: 220, height: 26)

            HStack {
                Button("Cancel") { sheet = nil }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Assign") { commit(item) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(pendingCombo == nil)
            }
        }
        .padding(20)
        .frame(width: 360)
        // Always starts empty. Carrying a value in from anywhere else would mean
        // Assign committing a shortcut the user never pressed on this screen.
        .onAppear { pendingCombo = nil }
    }

    private func commit(_ item: CatalogItem) {
        guard let pendingCombo, let target = target(for: item) else { return }
        service.assign(pendingCombo, to: target, name: item.title, symbolName: item.symbolName ?? item.category.symbolName)
        sheet = nil
        self.pendingCombo = nil
    }

    /// Only an app path or a Crest action can be bound. A settings pane or a
    /// shell command reaches the same place through the command bar, and binding
    /// a global key to each one is not what the shortcut list is for.
    private func target(for item: CatalogItem) -> HotKeyTarget? {
        switch item.action {
        case .launchApp(let path): .app(path: path)
        case .appAction(let id): .action(id: id)
        default: nil
        }
    }
}
