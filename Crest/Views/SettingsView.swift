//
//  SettingsView.swift
//  Crest
//

import SwiftUI

/// One pane of the settings window.
private enum SettingsPane: String, CaseIterable, Identifiable {
    case general = "General"
    case menuBar = "Menu Bar"
    case shortcuts = "Shortcuts"
    case aliases = "Aliases"
    case voice = "Voice"
    case tiling = "Tiling"
    case meetings = "Meetings"
    case cleaner = "Cleaner"
    case tools = "Tools"
    case about = "About"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .general: "gearshape"
        case .menuBar: "menubar.rectangle"
        case .shortcuts: "command"
        case .aliases: "text.badge.star"
        case .voice: "mic"
        case .tiling: "rectangle.split.2x2"
        case .meetings: "text.bubble"
        case .cleaner: "sparkles"
        case .tools: "wrench.and.screwdriver"
        case .about: "info.circle"
        }
    }
}

/// A sidebar rather than a row of tabs.
///
/// Seven panes do not fit across a 500-point window: as a `TabView` they
/// collapsed into a "»" overflow button, which hides four of them behind a menu
/// and gives no sense of what the window contains. A sidebar shows all seven at
/// once and has room for the next one.
struct SettingsView: View {
    @State private var pane: SettingsPane = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $pane) { each in
                Label(each.rawValue, systemImage: each.symbolName)
                    .tag(each)
            }
            .navigationSplitViewColumnWidth(178)
        } detail: {
            detail
                .navigationTitle(pane.rawValue)
        }
        .frame(minWidth: 700, minHeight: 520)
    }

    @ViewBuilder
    private var detail: some View {
        switch pane {
        case .general: GeneralSettingsTab()
        case .menuBar: MenuBarSettingsTab()
        case .shortcuts: HotKeysSettingsTab()
        case .aliases: AliasSettingsTab()
        case .voice: VoiceSettingsTab()
        case .tiling: TilingSettingsTab()
        case .meetings: MeetingsSettingsTab()
        case .cleaner: CleanerSettingsTab()
        case .tools: ToolsSettingsTab()
        case .about: AboutSettingsTab()
        }
    }
}

private struct GeneralSettingsTab: View {
    @Environment(CrestViewModel.self) private var viewModel

    var body: some View {
        @Bindable var viewModel = viewModel

        Form {
            Section {
                Toggle("Launch at login", isOn: $viewModel.launchAtLogin)
            } footer: {
                Text("Keeps the menu bar item and your shortcuts working after a restart, without opening a window.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Uninstall an app") {
                    Button("Open") { viewModel.openUninstaller() }
                }
                LabeledContent("Full Disk Access") {
                    Button("Open System Settings") { viewModel.openFullDiskAccessSettings() }
                }
            } footer: {
                Text("The uninstaller removes an app together with the support files, preferences, containers, caches, logs and startup items it leaves behind. Everything goes to the Trash. Full Disk Access lets the cleaner see caches macOS otherwise hides, so its figures are complete.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Free space", value: viewModel.volume.formattedFree)
                LabeledContent("Capacity", value: viewModel.volume.formattedTotal)
            } header: {
                Text("This Mac")
            } footer: {
                Text("Crest only reads your home folder. It never touches system files, and removal always goes through the Trash.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }
}

private struct CleanerSettingsTab: View {
    @Environment(CrestViewModel.self) private var viewModel

    var body: some View {
        @Bindable var viewModel = viewModel

        Form {
            Section {
                ForEach(CleanerCategory.allCases) { category in
                    Toggle(isOn: categoryBinding(for: category)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Label(category.rawValue, systemImage: category.iconName)
                            Text(category.blurb)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Preselect these types")
            } footer: {
                Text("Every type is still scanned and listed. This only controls what starts out ticked.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Only preselect items idle for", selection: $viewModel.policy.minimumAgeDays) {
                    Text("Any age").tag(0)
                    Text("1 day").tag(1)
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                }

                Picker("List items larger than", selection: $viewModel.policy.minimumItemBytes) {
                    Text("1 MB").tag(UInt64(1024 * 1024))
                    Text("10 MB").tag(UInt64(10 * 1024 * 1024))
                    Text("50 MB").tag(UInt64(50 * 1024 * 1024))
                    Text("100 MB").tag(UInt64(100 * 1024 * 1024))
                }
            } header: {
                Text("Thresholds")
            } footer: {
                Text("Anything smaller is still counted — it's grouped into a single row per category instead of listed individually.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
        .onChange(of: viewModel.policy) { _, _ in viewModel.persistPolicy() }
    }

    private func categoryBinding(for category: CleanerCategory) -> Binding<Bool> {
        Binding(
            get: { viewModel.policy.enabledCategories.contains(category) },
            set: { isOn in
                if isOn {
                    viewModel.policy.enabledCategories.insert(category)
                } else {
                    viewModel.policy.enabledCategories.remove(category)
                }
            }
        )
    }
}

private struct ToolsSettingsTab: View {
    @Environment(CrestViewModel.self) private var viewModel

    var body: some View {
        @Bindable var viewModel = viewModel

        Form {
            Section {
                Toggle("Search files as well as apps", isOn: $viewModel.fileSearchEnabled)
                Toggle("Preview the selected file", isOn: $viewModel.filePreviewEnabled)
                    .disabled(!viewModel.fileSearchEnabled)
            } header: {
                Text("File search")
            } footer: {
                Text("Files come from the Spotlight index macOS already keeps, so there is no second index and nothing to wait for. Type `f ` in front of a query to search files only, or paste a path to jump straight to it. ⌘↩ reveals in Finder, ⌘⇧C copies the path.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Keep clipboard history", isOn: Binding(
                    get: { viewModel.clipboard.isEnabled },
                    set: { viewModel.clipboard.isEnabled = $0 }
                ))
            } header: {
                Text("Clipboard")
            } footer: {
                Text("Keeps the last 150 items on disk. Content marked concealed or transient by password managers is never recorded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Copy colors as", selection: Binding(
                    get: { viewModel.colorPicker.format },
                    set: { viewModel.colorPicker.format = $0 }
                )) {
                    ForEach(ColorFormat.allCases) { Text($0.rawValue).tag($0) }
                }
                Toggle("Hex without the leading #", isOn: Binding(
                    get: { viewModel.colorPicker.bareHex },
                    set: { viewModel.colorPicker.bareHex = $0 }
                ))
            } header: {
                Text("Color picker")
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }
}
