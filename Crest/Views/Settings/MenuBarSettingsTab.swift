//
//  MenuBarSettingsTab.swift
//  Crest
//

import SwiftUI

/// What the menu bar shows, and which features the panel offers behind it.
///
/// The tab bar was a fixed row of ten icons, which is ten for everyone whether or
/// not they run Docker, use the clipboard history, or care about network traffic.
/// Choosing the set — and the order — is what makes the panel yours rather than a
/// tour of everything the app can do.
struct MenuBarSettingsTab: View {
    @Environment(CrestViewModel.self) private var viewModel

    var body: some View {
        @Bindable var viewModel = viewModel

        Form {
            Section {
                LabeledContent("Icon") {
                    HStack(spacing: 4) {
                        ForEach(MenuBarIcon.allCases) { option in
                            iconChoice(option)
                        }
                    }
                }

                Picker("Shows", selection: $viewModel.menuBarMetric) {
                    ForEach(MenuBarMetric.allCases) { Text($0.rawValue).tag($0) }
                }

                Toggle("Show the figure next to the icon", isOn: $viewModel.showFreeSpaceInMenuBar)
                    .disabled(viewModel.menuBarMetric == .none)
            } header: {
                Text("Menu bar")
            } footer: {
                Text("CPU and Memory keep a one-second sampler running even when the panel is closed. Free space and Battery cost nothing extra.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(Array(viewModel.sectionOrder.enumerated()), id: \.element) { index, section in
                    row(section, at: index)
                }
            } header: {
                HStack {
                    Text("Features in the panel")
                    Spacer()
                    Button("Reset") { viewModel.resetSections() }
                        .buttonStyle(.link)
                        .font(.caption)
                }
            } footer: {
                Text("Turned-off features leave the tab bar entirely. Use the arrows to put the one you open most first — that's the tab the panel lands on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }

    // MARK: - Rows

    private func row(_ section: PanelSection, at index: Int) -> some View {
        let isOn = viewModel.enabledSections.contains(section)
        // Every tab off would leave the panel with nothing to show, so the last
        // one standing cannot be turned off.
        let isLastEnabled = isOn && viewModel.enabledSections.count == 1

        return HStack(spacing: 9) {
            Image(systemName: section.iconName)
                .font(.system(size: 12))
                .foregroundStyle(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(section.rawValue)
                    .font(.system(size: 12.5))
                Text(section.blurb)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button {
                withAnimation(.snappy(duration: 0.16)) { viewModel.moveSection(section, by: -1) }
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(index == 0)
            .help("Move up")
            .accessibilityLabel("Move \(section.rawValue) up")

            Button {
                withAnimation(.snappy(duration: 0.16)) { viewModel.moveSection(section, by: 1) }
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(index == viewModel.sectionOrder.count - 1)
            .help("Move down")
            .accessibilityLabel("Move \(section.rawValue) down")

            Toggle("", isOn: Binding(
                get: { isOn },
                set: { viewModel.setSection(section, enabled: $0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .disabled(isLastEnabled)
            .help(isLastEnabled ? "At least one feature has to stay on" : "Show \(section.rawValue) in the panel")
        }
        .padding(.vertical, 2)
    }

    /// Swatches rather than a menu of names: the icon is the thing being chosen,
    /// so showing it is both faster to scan and unambiguous.
    private func iconChoice(_ option: MenuBarIcon) -> some View {
        let isSelected = viewModel.menuBarIcon == option

        return Button {
            viewModel.menuBarIcon = option
        } label: {
            Image(systemName: option.symbolName)
                .font(.system(size: 13))
                .frame(width: 26, height: 24)
                .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? AnyShapeStyle(.tint.opacity(0.18)) : AnyShapeStyle(.clear))
                )
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(option.rawValue)
        .accessibilityLabel(option.rawValue)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}
