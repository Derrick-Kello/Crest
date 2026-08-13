//
//  ToolsSectionView.swift
//  DiskPilot
//

import SwiftUI

/// Keep Awake, the colour picker, and the command bar — the three things you
/// reach for directly rather than reading.
struct ToolsSectionView: View {
    @Environment(DiskPilotViewModel.self) private var viewModel

    private var keepAwake: KeepAwakeService { viewModel.keepAwake }

    var body: some View {
        PanelCard(section: .tools) {
            if keepAwake.isActive {
                HStack(spacing: 3) {
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.system(size: 10))
                    Text(keepAwake.duration.shortLabel)
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(.orange)
            }
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                keepAwakeBlock
                Divider().padding(.vertical, 1)
                colorBlock
                Divider().padding(.vertical, 1)
                commandBarBlock
            }
        }
    }

    // MARK: - Keep awake

    private var keepAwakeBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: keepAwake.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                    .font(.system(size: 12))
                    .foregroundStyle(keepAwake.isActive ? .orange : .secondary)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Keep Awake")
                        .font(.system(size: 12, weight: .medium))
                    Text(keepAwake.isActive
                         ? (keepAwake.remainingDescription ?? "Sleep is prevented")
                         : "Your Mac sleeps normally")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { keepAwake.isActive },
                    set: { _ in keepAwake.toggle() }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .accessibilityLabel("Keep Awake")
            }

            HStack(spacing: 6) {
                Picker("", selection: Binding(
                    get: { keepAwake.duration },
                    set: { newValue in
                        keepAwake.duration = newValue
                        // Restart so a running session adopts the new duration
                        // instead of silently keeping the old deadline.
                        if keepAwake.isActive { keepAwake.start() }
                    }
                )) {
                    ForEach(KeepAwakeDuration.allCases) { duration in
                        Text(duration.rawValue).tag(duration)
                    }
                }
                .labelsHidden()
                .controlSize(.small)

                Toggle(isOn: Binding(
                    get: { keepAwake.allowDisplaySleep },
                    set: { newValue in
                        keepAwake.allowDisplaySleep = newValue
                        if keepAwake.isActive { keepAwake.start() }
                    }
                )) {
                    Text("Screen may sleep")
                        .font(.system(size: 10))
                }
                .toggleStyle(.checkbox)
                .controlSize(.small)
            }
        }
    }

    // MARK: - Colour picker

    private var colorBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "eyedropper")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Colour picker")
                        .font(.system(size: 12, weight: .medium))
                    Text(viewModel.lastPickedColor ?? "Sample any pixel on screen")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .monospaced()
                }

                Spacer()

                Picker("", selection: Binding(
                    get: { viewModel.colorPicker.format },
                    set: { viewModel.colorPicker.format = $0 }
                )) {
                    ForEach(ColorFormat.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .controlSize(.mini)
                .frame(width: 82)

                Button {
                    Task { await viewModel.pickColor() }
                } label: {
                    Text("Pick").font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if !viewModel.colorPicker.recent.isEmpty {
                HStack(spacing: 4) {
                    ForEach(viewModel.colorPicker.recent.prefix(10)) { picked in
                        Button {
                            viewModel.colorPicker.copy(picked)
                            viewModel.statusMessage = "Copied \(picked.string(in: viewModel.colorPicker.format, bareHex: viewModel.colorPicker.bareHex))"
                        } label: {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(picked.color)
                                .frame(width: 20, height: 20)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .strokeBorder(.white.opacity(0.25), lineWidth: 0.5)
                                )
                        }
                        .buttonStyle(.plain)
                        .help(picked.string(in: viewModel.colorPicker.format, bareHex: viewModel.colorPicker.bareHex))
                    }
                    Spacer()
                }
                .padding(.leading, 24)
            }
        }
    }

    // MARK: - Command bar

    private var commandBarBlock: some View {
        HStack(spacing: 8) {
            Image(systemName: "command")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text("Command bar")
                    .font(.system(size: 12, weight: .medium))
                if viewModel.hotKeyRegistrationFailed {
                    Text("\(viewModel.commandBarHotKey.displayString) is taken by another app")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                } else {
                    Text("Press \(viewModel.commandBarHotKey.displayString) anywhere")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                viewModel.showCommandBar()
            } label: {
                Text("Open").font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}
