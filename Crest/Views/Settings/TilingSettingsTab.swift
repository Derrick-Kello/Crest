//
//  TilingSettingsTab.swift
//  Crest
//

import AppKit
import SwiftUI

/// Everything about the window manager: whether it runs, how much air is between
/// the windows, which apps it leaves alone, and the whole key map.
struct TilingSettingsTab: View {
    private var engine: TilingEngine { TilingEngine.shared }
    private var keys: TilingHotKeyService { TilingHotKeyService.shared }

    @State private var isTrusted = AX.isTrusted
    @State private var innerGap = Preferences.tilingInnerGap
    @State private var outerGap = Preferences.tilingOuterGap
    @State private var animate = Preferences.tilingAnimations
    @State private var excluded = Preferences.tilingExcludedBundleIDs

    var body: some View {
        Form {
            enableSection
            if isTrusted { gapsSection }
            keymapSection
            excludedSection
        }
        .formStyle(.grouped)
        // Permission is granted in System Settings, in another process, and macOS
        // sends no notification when it happens. Re-checking when the window comes
        // back is what turns the rest of this pane on without a relaunch.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            isTrusted = AX.isTrusted
        }
    }

    // MARK: - Enable

    private var enableSection: some View {
        Section {
            Toggle("Tile my windows", isOn: Binding(
                get: { engine.isRunning },
                set: { shouldRun in
                    shouldRun ? engine.start() : engine.stop()
                    Preferences.tilingEnabled = engine.isRunning
                    keys.registerAll()
                    isTrusted = AX.isTrusted
                }
            ))

            if !isTrusted { permissionRow }
        } header: {
            Text("Window manager")
        } footer: {
            Text("Windows are arranged side by side instead of stacked, and \(keys.modifier.symbols)1 through \(keys.modifier.symbols)9 switch between nine workspaces. Everything can be undone by turning this off, which puts every window back on screen.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// What to say when the API refuses.
    ///
    /// Split by cause, because the two cases need opposite advice: an ungranted
    /// app needs the settings pane, and an app whose grant went stale needs the
    /// old record removed first — sending that user to the settings pane shows
    /// them a switch that is already on and teaches them nothing.
    @ViewBuilder
    private var permissionRow: some View {
        switch AX.diagnose() {
        case .granted:
            EmptyView()

        case .notAsked:
            HStack {
                Text("Accessibility permission is needed before Crest can move a window.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Spacer()
                Button("Grant") {
                    AX.requestTrust()
                    AX.openAccessibilitySettings()
                }
                .controlSize(.small)
            }

        case .staleRecord(let grantedCopy):
            VStack(alignment: .leading, spacing: 6) {
                Text("Accessibility looks enabled, but macOS granted it to a different build of Crest.")
                    .font(.caption)
                    .foregroundStyle(.orange)

                Text(staleExplanation(grantedCopy: grantedCopy))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Button("Reset and ask again") {
                        AX.resetTrust()
                        AX.requestTrust()
                        AX.openAccessibilitySettings()
                    }
                    Button("Open settings") { AX.openAccessibilitySettings() }
                }
                .controlSize(.small)
            }
            .padding(.vertical, 2)
        }
    }

    private func staleExplanation(grantedCopy: String?) -> String {
        let where_ = grantedCopy.map { "The switch belongs to \($0). " } ?? ""
        return where_ + "Crest is signed ad hoc, with no developer certificate, so macOS pins the permission to that one exact binary rather than to the app. Rebuilding produces a new binary and the grant no longer matches. Resetting removes every Accessibility record for Crest so this build can ask for its own."
    }

    // MARK: - Gaps

    private var gapsSection: some View {
        Section {
            LabeledContent("Between windows") {
                Stepper(value: $innerGap, in: 0 ... 40) {
                    Text("\(innerGap) pt").monospacedDigit()
                }
                .onChange(of: innerGap) { _, value in
                    Preferences.tilingInnerGap = value
                    engine.apply()
                }
            }

            LabeledContent("Around the screen") {
                Stepper(value: $outerGap, in: 0 ... 60) {
                    Text("\(outerGap) pt").monospacedDigit()
                }
                .onChange(of: outerGap) { _, value in
                    Preferences.tilingOuterGap = value
                    engine.apply()
                }
            }

            Toggle("Slide windows into place", isOn: $animate)
                .onChange(of: animate) { _, value in Preferences.tilingAnimations = value }
        } header: {
            Text("Gaps and motion")
        } footer: {
            Text("macOS has no way to animate another app's window, so Crest moves each one a frame at a time. It is a fifth of a second and costs nothing on a modern Mac, but turn it off if your desktop is busy and the movement stutters.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Key map

    private var keymapSection: some View {
        // Read once, here, rather than inside the row builders below. The rows are
        // built lazily by `ForEach`, and a value read inside a lazy builder does
        // not make this view depend on it — which is why changing the modifier
        // rebound every key and redrew none of them.
        let bindings = keys.bindings
        let modifier = keys.modifier

        return Section {
            Picker("Modifier", selection: Binding(
                get: { modifier },
                set: { keys.setModifier($0) }
            )) {
                ForEach(TilingModifier.allCases) { option in
                    Text("\(option.symbols)  \(option == .commandControl ? "(recommended)" : "")")
                        .tag(option)
                }
            }

            if let caution = modifier.caution {
                Text(caution)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(TilingKeymap.groups, id: \.self) { group in
                DisclosureGroup(group) {
                    ForEach(bindings.filter { $0.group == group }) { binding in
                        bindingRow(binding)
                    }
                }
            }
            // Rows are identified by command, and the command does not change when
            // the modifier does — so without this, SwiftUI reuses each row and the
            // recorder inside it keeps drawing the key it was built with. Changing
            // the identity of the whole list is what forces the new keys on screen.
            .id(modifier)

            Button("Reset every shortcut to its default") {
                keys.resetToDefaults()
            }
            .buttonStyle(.link)
        } header: {
            Text("Shortcuts")
        } footer: {
            Text("The modifier stands in for Omarchy's SUPER key, and every shortcut hangs off it. Changing it rebinds the whole map and clears anything you recorded by hand. ⌘ alone is never offered: ⌘W, ⌘Q and ⌘1 already mean something in every app on the Mac. Shift is never offered either, because it is the second level here and ⇧1 is just an exclamation mark.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func bindingRow(_ binding: TilingBinding) -> some View {
        LabeledContent(binding.title) {
            HStack(spacing: 6) {
                if keys.failedIdentifiers.contains(binding.id) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help("Another app already holds this key.")
                }

                ShortcutRecorder(
                    combo: Binding(
                        get: { binding.combo },
                        set: { combo in
                            guard let combo else { return }
                            keys.rebind(binding, to: combo)
                        }
                    ),
                    conflict: { combo in
                        keys.bindings.first { $0.id != binding.id && $0.combo == combo }?.title
                            ?? UserHotKeyService.shared.conflict(for: combo, excluding: nil)
                    },
                    placeholder: "Click to record"
                )
                .frame(width: 130, height: 22)
            }
        }
    }

    // MARK: - Excluded apps

    private var excludedSection: some View {
        Section {
            if excluded.isEmpty {
                Text("No apps excluded. Crest already leaves System Settings, dialogs and anything that refuses to be resized alone.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(excluded.sorted(), id: \.self) { bundleID in
                    HStack {
                        Text(displayName(for: bundleID))
                        Spacer()
                        Button {
                            excluded.remove(bundleID)
                            Preferences.tilingExcludedBundleIDs = excluded
                            engine.refresh()
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Stop excluding \(displayName(for: bundleID))")
                    }
                }
            }

            Menu("Exclude an app") {
                ForEach(runningApps(), id: \.0) { bundleID, name in
                    Button(name) {
                        excluded.insert(bundleID)
                        Preferences.tilingExcludedBundleIDs = excluded
                        engine.refresh()
                    }
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        } header: {
            Text("Leave these apps alone")
        } footer: {
            Text("An excluded app keeps whatever size and position you give it, and never takes a slot in the layout.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// The apps that are open now and not already excluded — the list is for
    /// picking from, so an app you cannot see is not a useful row.
    private func runningApps() -> [(String, String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                guard let bundleID = app.bundleIdentifier,
                      !excluded.contains(bundleID),
                      !WindowEnumerator.neverTile.contains(bundleID)
                else { return nil }
                return (bundleID, app.localizedName ?? bundleID)
            }
            .sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
    }

    private func displayName(for bundleID: String) -> String {
        NSWorkspace.shared.runningApplications
            .first { $0.bundleIdentifier == bundleID }?
            .localizedName ?? bundleID
    }
}
