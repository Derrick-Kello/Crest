//
//  TilingSectionView.swift
//  Crest
//

import SwiftUI

/// The window manager in the menu-bar panel: which workspace you are on, what is
/// on each of the others, and the layout the current one is using.
///
/// Every control here has a keyboard shortcut that does the same thing, and the
/// shortcuts are the point — this exists for the moments when you have forgotten
/// which workspace something is on, which a key press cannot answer.
struct TilingSectionView: View {
    @Environment(CrestViewModel.self) private var viewModel

    private var engine: TilingEngine { TilingEngine.shared }

    var body: some View {
        PanelCard(section: .tiling) {
            if engine.isRunning {
                Text("Workspace \(engine.activeWorkspace)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                if !AX.isTrusted {
                    permissionState
                } else if engine.isRunning {
                    runningState
                } else {
                    idleState
                }
            }
        }
    }

    // MARK: - States

    @ViewBuilder
    private var permissionState: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch AX.diagnose() {
            case .granted:
                EmptyView()

            case .notAsked:
                Text("Tiling needs Accessibility permission before it can move a window. Nothing is read from your screen. The permission is what lets one app resize another's windows.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Grant permission") {
                    AX.requestTrust()
                    AX.openAccessibilitySettings()
                }
                .controlSize(.small)

            case .staleRecord(let grantedCopy):
                staleRecordState(grantedCopy: grantedCopy)
            }
        }
    }

    /// The switch is on and the API still says no.
    ///
    /// Worth its own explanation rather than repeating "grant permission", because
    /// the user has already done that and the obvious next move — toggling the
    /// switch again — does not fix it. macOS lists one row per app but grants to
    /// one exact binary, and this build is not the one it remembers.
    private func staleRecordState(grantedCopy: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Accessibility looks enabled, but macOS granted it to a different build of Crest.")
                .font(.system(size: 11, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)

            Text(explanation(grantedCopy: grantedCopy))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button("Reset and ask again") {
                    AX.resetTrust()
                    AX.requestTrust()
                    AX.openAccessibilitySettings()
                }
                Button("Open settings") { AX.openAccessibilitySettings() }
            }
            .controlSize(.small)
        }
    }

    private func explanation(grantedCopy: String?) -> String {
        if let grantedCopy {
            return "The switch belongs to \(grantedCopy). This copy is signed ad hoc, so the permission is pinned to that exact binary and does not carry over. Resetting removes the old entry so you can grant this one."
        }
        return "This copy is signed ad hoc, so macOS pins the permission to the exact binary and every rebuild invalidates it. Resetting removes the stale entry so you can grant it again."
    }

    private var idleState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Arranges your windows side by side instead of stacked, with nine workspaces on ⌥1 through ⌥9.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Start tiling") {
                engine.start()
                TilingHotKeyService.shared.registerAll()
                Preferences.tilingEnabled = engine.isRunning
            }
            .controlSize(.small)
        }
    }

    private var runningState: some View {
        VStack(alignment: .leading, spacing: 10) {
            workspaceStrip
            layoutPicker

            if let status = engine.status {
                Text(status)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button("Re-tile") { engine.refresh() }
                Button("Stop") {
                    engine.stop()
                    Preferences.tilingEnabled = false
                }
            }
            .controlSize(.small)
        }
    }

    // MARK: - Pieces

    /// Nine buttons, each showing how many windows it holds. The count is what
    /// makes the strip worth looking at — an empty workspace and a full one are
    /// otherwise indistinguishable until you switch to it.
    private var workspaceStrip: some View {
        HStack(spacing: 4) {
            ForEach(engine.workspaces) { workspace in
                let isActive = workspace.index == engine.activeWorkspace
                Button {
                    engine.switchTo(workspace: workspace.index)
                } label: {
                    VStack(spacing: 1) {
                        Text("\(workspace.index)")
                            .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                        Circle()
                            .frame(width: 3, height: 3)
                            .opacity(workspace.order.isEmpty ? 0 : 1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(isActive ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.05))
                    )
                    .foregroundStyle(isActive ? Color.accentColor : .primary)
                }
                .buttonStyle(.plain)
                .help(helpText(for: workspace))
            }
        }
    }

    private var layoutPicker: some View {
        HStack(spacing: 6) {
            ForEach(LayoutMode.allCases) { mode in
                let isActive = engine.workspaces[engine.activeWorkspace - 1].mode == mode
                Button {
                    engine.setLayout(mode)
                } label: {
                    Label(mode.title, systemImage: mode.symbolName)
                        .labelStyle(.iconOnly)
                        .font(.system(size: 11))
                        .frame(width: 26, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(isActive ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.05))
                        )
                        .foregroundStyle(isActive ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help(mode.title)
            }

            Spacer()

            Text("⌥E to cycle")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    /// The apps on a workspace, so hovering a number answers "where did I put it".
    private func helpText(for workspace: TilingWorkspace) -> String {
        let names = workspace.order
            .compactMap { TilingEngine.shared.windows[$0]?.appName }
            .reduce(into: [String]()) { unique, name in
                if !unique.contains(name) { unique.append(name) }
            }
        return names.isEmpty ? "Workspace \(workspace.index) — empty" : names.joined(separator: ", ")
    }
}
