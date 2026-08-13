//
//  SettingsView.swift
//  DiskPilot
//

import Carbon.HIToolbox
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            CleanerSettingsTab()
                .tabItem { Label("Cleaner", systemImage: "sparkles") }
            ToolsSettingsTab()
                .tabItem { Label("Tools", systemImage: "wrench.and.screwdriver") }
        }
        .frame(width: 470)
    }
}

private struct GeneralSettingsTab: View {
    @Environment(DiskPilotViewModel.self) private var viewModel

    var body: some View {
        @Bindable var viewModel = viewModel

        Form {
            Section {
                Toggle("Launch at login", isOn: $viewModel.launchAtLogin)
                Toggle("Show Docker section", isOn: $viewModel.dockerIntegrationEnabled)
            }

            Section {
                Picker("Menu bar shows", selection: $viewModel.menuBarMetric) {
                    ForEach(MenuBarMetric.allCases) { Text($0.rawValue).tag($0) }
                }
            } footer: {
                Text("CPU and Memory keep a one-second sampler running even when the panel is closed. Free space and Battery cost nothing extra.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Free space", value: viewModel.volume.formattedFree)
                LabeledContent("Capacity", value: viewModel.volume.formattedTotal)
            } header: {
                Text("This Mac")
            } footer: {
                Text("DiskPilot only reads your home folder. It never touches system files, and removal always goes through the Trash.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }
}

private struct CleanerSettingsTab: View {
    @Environment(DiskPilotViewModel.self) private var viewModel

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
    @Environment(DiskPilotViewModel.self) private var viewModel

    var body: some View {
        @Bindable var viewModel = viewModel

        Form {
            Section {
                Toggle("Enable the command bar shortcut", isOn: $viewModel.commandBarEnabled)
                Picker("Shortcut", selection: $viewModel.commandBarHotKey) {
                    ForEach(Self.shortcutChoices, id: \.self) { combo in
                        Text(combo.displayString).tag(combo)
                    }
                }
                .disabled(!viewModel.commandBarEnabled)
            } header: {
                Text("Command bar")
            } footer: {
                if viewModel.hotKeyRegistrationFailed {
                    Text("\(viewModel.commandBarHotKey.displayString) is already claimed by another app. Pick a different one.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Text("Search apps, run DiskPilot actions, do arithmetic, or paste from clipboard history.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
                Picker("Copy colours as", selection: Binding(
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
                Text("Colour picker")
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }

    /// A short list of combinations unlikely to collide with system shortcuts.
    private static let shortcutChoices: [HotKeyCombo] = [
        HotKeyCombo(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey)),
        HotKeyCombo(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey)),
        HotKeyCombo(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey | shiftKey)),
        HotKeyCombo(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(optionKey | cmdKey)),
        HotKeyCombo(keyCode: UInt32(kVK_ANSI_D), modifiers: UInt32(optionKey | cmdKey)),
    ]
}
