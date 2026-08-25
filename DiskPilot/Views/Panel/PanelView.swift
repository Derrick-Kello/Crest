//
//  PanelView.swift
//  DiskPilot
//

import SwiftUI

/// The whole app, as one menu-bar panel.
///
/// There is no main window and no sidebar. The previous design split one dataset
/// across seven navigable sections — Overview, Findings, Map, Developer Cleanup —
/// which meant the user had to know where to look before they could do anything.
/// Here one icon tab bar switches between sections, each owning a single job, and
/// only the selected one is built.
struct PanelView: View {
    @Environment(DiskPilotViewModel.self) private var viewModel

    /// A `ScrollView` reports no useful ideal height, and the menu-bar window sizes
    /// itself to its content — so without measuring, the panel gets clipped to an
    /// arbitrary height and the lower part of a section simply vanishes. Measuring
    /// lets the window fit the section until it hits the cap, then scroll.
    @State private var contentHeight: CGFloat = 0

    private var scrollHeight: CGFloat {
        min(max(contentHeight, 60), 520)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            PanelTabBar()
                .padding(.horizontal, 10)
                .padding(.bottom, 8)

            ScrollView {
                selectedSection
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: scrollHeight)

            footer
        }
        .frame(width: PanelMetrics.width)
        .task { viewModel.panelDidAppear() }
        .onDisappear { viewModel.panelDidDisappear() }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.dismissError() } }
            )
        ) {
            Button("OK") { viewModel.dismissError() }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    /// Switching tabs replaces the view outright rather than hiding a sibling, so
    /// an unselected section holds no state and costs nothing.
    @ViewBuilder
    private var selectedSection: some View {
        switch viewModel.selectedSection {
        case .system: SystemSectionView()
        case .disk: DiskSectionView()
        case .cleaner: CleanerSectionView()
        case .network: NetworkSectionView()
        case .power: PowerSectionView()
        case .tools: ToolsSectionView()
        case .clipboard: ClipboardSectionView()
        case .largeFolders: LargeFoldersSectionView()
        case .docker: DockerSectionView()
        case .homebrew: HomebrewSectionView()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "internaldrive.fill")
                .font(.system(size: 13))
                .foregroundStyle(viewModel.health.color)

            Text("DiskPilot")
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            // Icon-only controls carry no implicit label, so each one is named
            // explicitly — `help` is a tooltip, not something VoiceOver reads.
            Button {
                Task { await viewModel.runScan() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(viewModel.isScanning)
            .help("Scan for cleanable files")
            .accessibilityLabel("Scan")

            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Settings")
            .accessibilityLabel("Settings")

            Button {
                viewModel.quit()
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Quit DiskPilot")
            .accessibilityLabel("Quit DiskPilot")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var footer: some View {
        if let message = viewModel.statusMessage {
            Divider()
            Text(message)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
        }
    }
}
