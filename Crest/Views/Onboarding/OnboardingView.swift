//
//  OnboardingView.swift
//  Crest
//

import AppKit
import Carbon.HIToolbox
import SwiftUI

/// First-run setup.
///
/// Five steps, each one a decision the app would otherwise make silently and get
/// wrong for somebody: where the shortcut lives, what the menu bar shows, which
/// features are worth a tab, and whether Crest may see the folders it is being
/// asked to clean. Every step can be skipped and every choice is in Settings
/// afterwards, so nothing here is a gate.
struct OnboardingView: View {
    @Environment(CrestViewModel.self) private var viewModel
    let onFinish: () -> Void

    @State private var step: Step = .welcome

    enum Step: Int, CaseIterable {
        case welcome, shortcut, menuBar, features, permissions, done

        var title: String {
            switch self {
            case .welcome: "Welcome to Crest"
            case .shortcut: "One key opens everything"
            case .menuBar: "What the menu bar shows"
            case .features: "Pick your features"
            case .permissions: "Two last things"
            case .done: "You're set"
            }
        }

        var subtitle: String {
            switch self {
            case .welcome:
                "Storage, system load, battery, cleanup and a launcher — all from the menu bar, with no window in the way."
            case .shortcut:
                "The command bar searches your apps, files, settings panes and Crest's own tools. Pick the shortcut that opens it."
            case .menuBar:
                "Crest lives as one item in the menu bar. Choose its glyph and the figure beside it."
            case .features:
                "Only the ones you turn on get a tab. You can change this any time in Settings."
            case .permissions:
                "Full Disk Access lets the cleaner see the caches your developer tools leave behind. Launching at login keeps the shortcut working after a restart."
            case .done:
                "Everything here is in Settings if you change your mind."
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 34)
                .padding(.top, 34)

            footer
        }
        .frame(width: 560, height: 470)
        .background(.regularMaterial)
    }

    // MARK: - Steps

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                Text(step.title)
                    .font(.system(size: 22, weight: .semibold))
                Text(step.subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            switch step {
            case .welcome: welcomeStep
            case .shortcut: shortcutStep
            case .menuBar: menuBarStep
            case .features: featuresStep
            case .permissions: permissionsStep
            case .done: doneStep
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            highlight("internaldrive", "See where your space went", "Free space, the biggest folders, and what is safe to reclaim.")
            highlight("sparkles", "Clean without guessing", "Every item is listed with its size and risk before anything moves, and removal goes to the Trash.")
            highlight("magnifyingglass", "Launch anything", "Apps, files, settings panes, clipboard history and arithmetic, from one shortcut.")
            highlight("trash.slash", "Uninstall properly", "Removes an app together with the support files, caches and login items it leaves behind.")
        }
        .padding(.top, 4)
    }

    private var shortcutStep: some View {
        @Bindable var viewModel = viewModel

        return VStack(alignment: .leading, spacing: 14) {
            Toggle("Enable the command bar", isOn: $viewModel.commandBarEnabled)

            HStack(spacing: 12) {
                Text("Shortcut")
                    .font(.system(size: 13))
                ShortcutRecorder(
                    combo: Binding(
                        get: { viewModel.commandBarHotKey },
                        set: { if let combo = $0 { viewModel.commandBarHotKey = combo } }
                    ),
                    placeholder: "Click, then press keys"
                )
                .frame(width: 190, height: 26)
                .disabled(!viewModel.commandBarEnabled)
            }

            if viewModel.hotKeyRegistrationFailed {
                Label(
                    "\(viewModel.commandBarHotKey.displayString) is already claimed by another app. Record a different one.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.callout)
                .foregroundStyle(.orange)
            } else if viewModel.commandBarEnabled {
                Label(
                    "Press \(viewModel.commandBarHotKey.displayString) anywhere to open it.",
                    systemImage: "checkmark.circle"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            Text("You can also give individual apps their own shortcut later — Settings › Shortcuts.")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }

    private var menuBarStep: some View {
        @Bindable var viewModel = viewModel

        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Icon").font(.system(size: 12, weight: .medium))
                HStack(spacing: 6) {
                    ForEach(MenuBarIcon.allCases) { option in
                        Button {
                            viewModel.menuBarIcon = option
                        } label: {
                            Image(systemName: option.symbolName)
                                .font(.system(size: 15))
                                .frame(width: 36, height: 32)
                                .foregroundStyle(viewModel.menuBarIcon == option ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                                .background(
                                    RoundedRectangle(cornerRadius: 7)
                                        .fill(viewModel.menuBarIcon == option ? AnyShapeStyle(.tint.opacity(0.16)) : AnyShapeStyle(.quaternary.opacity(0.4)))
                                )
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .help(option.rawValue)
                        .accessibilityLabel(option.rawValue)
                    }
                }
            }

            Picker("Shows", selection: $viewModel.menuBarMetric) {
                ForEach(MenuBarMetric.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)
            .frame(width: 260)

            HStack(spacing: 8) {
                Text("Preview")
                    .font(.system(size: 12, weight: .medium))
                HStack(spacing: 4) {
                    Image(systemName: viewModel.menuBarIcon.symbolName)
                        .font(.system(size: 13, weight: .medium))
                    if viewModel.menuBarMetric != .none {
                        Text(viewModel.menuBarTitle)
                            .font(.system(size: 12, weight: .medium))
                            .monospacedDigit()
                    }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 6))
            }
        }
        .padding(.top, 4)
    }

    private var featuresStep: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(viewModel.sectionOrder, id: \.self) { section in
                    featureRow(section)
                    if section != viewModel.sectionOrder.last { Divider() }
                }
            }
            .padding(.trailing, 8)
        }
        // Ten features do not fit a 470-point window, so the list scrolls — but
        // it has to start at the top. Left to itself the scroll view follows
        // whichever control took keyboard focus, which opened the step already
        // scrolled past the first four features.
        .defaultScrollAnchor(.top)
        .frame(maxHeight: 300)
    }

    /// Laid out as an explicit row rather than a `Toggle` with a label: a switch
    /// placed by the toggle itself sits wherever its own label ends, so ten rows
    /// with ten different label widths put the switches in ten different places.
    private func featureRow(_ section: PanelSection) -> some View {
        let isOn = viewModel.enabledSections.contains(section)
        // The panel would have nothing to show with every feature off.
        let isLastEnabled = isOn && viewModel.enabledSections.count == 1

        return HStack(spacing: 10) {
            Image(systemName: section.iconName)
                .font(.system(size: 13))
                .foregroundStyle(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(section.rawValue)
                    .font(.system(size: 12.5))
                Text(section.blurb)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            Toggle("", isOn: Binding(
                get: { isOn },
                set: { viewModel.setSection(section, enabled: $0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(isLastEnabled)
            .accessibilityLabel(section.rawValue)
            .help(isLastEnabled ? "At least one feature has to stay on" : section.blurb)
        }
        .padding(.vertical, 6)
    }

    private var permissionsStep: some View {
        @Bindable var viewModel = viewModel

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "lock.open")
                    .font(.system(size: 16))
                    .foregroundStyle(.tint)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Full Disk Access").font(.system(size: 13, weight: .medium))
                    Text("Without it the cleaner cannot see some caches, and the sizes it reports will be low.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button("Open") { viewModel.openFullDiskAccessSettings() }
            }
            .padding(12)
            .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 10))

            Toggle("Launch Crest at login", isOn: $viewModel.launchAtLogin)

            Text("Neither is required. Crest runs without them — it just sees less.")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .padding(.top, 4)
    }

    private var doneStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.commandBarEnabled {
                highlight("magnifyingglass", "Press \(viewModel.commandBarHotKey.displayString)", "Opens the command bar from anywhere.")
            }
            highlight(viewModel.menuBarIcon.symbolName, "Click the menu bar icon", "Everything else lives behind it.")
            highlight("sparkles", "Run your first scan", "The Cleaner tab lists what is safe to reclaim before it removes anything.")
        }
        .padding(.top, 4)
    }

    private func highlight(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundStyle(.tint)
                .frame(width: 24, height: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            if step != .welcome {
                Button("Back") { move(-1) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 5) {
                ForEach(Step.allCases, id: \.rawValue) { each in
                    Circle()
                        .fill(each == step ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                        .frame(width: 5, height: 5)
                }
            }
            .accessibilityLabel("Step \(step.rawValue + 1) of \(Step.allCases.count)")

            Spacer()

            if step != .done {
                Button("Skip") { onFinish() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }

            Button(step == .done ? "Start using Crest" : "Continue") {
                step == .done ? onFinish() : move(1)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.quaternary.opacity(0.22))
    }

    private func move(_ delta: Int) {
        let next = step.rawValue + delta
        guard let target = Step(rawValue: next) else { return }
        withAnimation(.snappy(duration: 0.2)) { step = target }
    }
}
