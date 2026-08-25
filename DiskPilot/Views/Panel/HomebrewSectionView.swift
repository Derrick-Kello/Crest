//
//  HomebrewSectionView.swift
//  DiskPilot
//

import SwiftUI

/// Homebrew, in the panel: what is installed, what has an update, and what the
/// package cache is costing in disk space.
///
/// The section is a disk feature as much as a package manager. `brew cleanup`'s
/// reclaimable figure sits in the footer next to the same kind of button the
/// Docker section uses, because stale bottles are one of the larger recurring
/// caches on a developer's Mac and nothing else in the app can see them.
struct HomebrewSectionView: View {
    @Environment(DiskPilotViewModel.self) private var viewModel

    @State private var query = ""
    @State private var pending: PendingAction?

    private var brew: HomebrewService { viewModel.homebrew }

    /// What the user typed narrows the installed list immediately, and separately
    /// asks Homebrew for packages that aren't on the Mac yet.
    private var filteredInstalled: [BrewPackage] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let packages = trimmed.isEmpty
            ? brew.installed
            : brew.installed.filter {
                $0.name.localizedCaseInsensitiveContains(trimmed)
                    || $0.summary.localizedCaseInsensitiveContains(trimmed)
            }
        // Anything with an update waiting goes to the top: it is the only row in
        // the list that needs a decision.
        return packages.sorted { lhs, rhs in
            if lhs.isOutdated != rhs.isOutdated { return lhs.isOutdated }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    var body: some View {
        PanelCard(section: .homebrew) {
            header
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                switch brew.availability {
                case .unknown:
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity)
                case .missing:
                    missingBlock
                case .ready:
                    readyBlock
                }
            }
        }
        .task { await viewModel.refreshHomebrew() }
        .confirmationDialog(
            pending?.title ?? "",
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            titleVisibility: .visible
        ) {
            if let pending {
                Button(pending.verb, role: pending.isDestructive ? .destructive : nil) {
                    let action = pending.run
                    Task { await action() }
                }
                Button("Cancel", role: .cancel) {}
            }
        } message: {
            Text(pending?.message ?? "")
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        if brew.isLoading {
            ProgressView().controlSize(.mini)
        } else if !brew.outdated.isEmpty {
            Text("\(brew.outdated.count) update\(brew.outdated.count == 1 ? "" : "s")")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.orange)
        } else if brew.availability.isReady {
            Text("\(brew.installed.count) packages")
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Not installed

    private var missingBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Homebrew isn't installed, so packages can't be managed from here yet.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button {
                    brew.openInstallerInTerminal()
                } label: {
                    Text("Install Homebrew").font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    Task { await viewModel.refreshHomebrew(force: true) }
                } label: {
                    Text("Check again").font(.system(size: 10))
                }
                .buttonStyle(.link)
            }

            Text("Terminal opens with the official installer, shows every step and asks for your password if it needs one. Come back and click Check again when it finishes.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Installed

    @ViewBuilder
    private var readyBlock: some View {
        searchField

        if let operation = brew.operation {
            operationBlock(operation)
        }

        if let failure = brew.failure {
            failureBlock(failure)
        }

        if !brew.outdated.isEmpty, query.isEmpty {
            updateAllRow
        }

        if filteredInstalled.isEmpty, brew.searchResults.isEmpty, !brew.isSearching {
            Text(query.isEmpty ? "No packages installed yet." : "No packages found.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }

        ForEach(filteredInstalled.prefix(query.isEmpty ? 8 : 6)) { package in
            packageRow(package)
        }

        if query.isEmpty, filteredInstalled.count > 8 {
            Text("and \(filteredInstalled.count - 8) more — search to narrow the list")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }

        if !brew.searchResults.isEmpty || brew.isSearching {
            Divider().padding(.vertical, 2)
            HStack(spacing: 6) {
                Text("Available to install")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                if brew.isSearching { ProgressView().controlSize(.mini) }
                Spacer()
            }
            ForEach(brew.searchResults.prefix(6)) { package in
                packageRow(package)
            }
        }

        Divider().padding(.vertical, 2)
        footer
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)

            TextField("Search formulae and casks", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .onChange(of: query) { _, newValue in
                    brew.search(newValue)
                }

            if !query.isEmpty {
                Button {
                    query = ""
                    brew.clearSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 7))
    }

    private func packageRow(_ package: BrewPackage) -> some View {
        HStack(spacing: 8) {
            Image(systemName: package.isCask ? "app.dashed" : "shippingbox")
                .font(.system(size: 11))
                .foregroundStyle(package.isOutdated ? .orange : .secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(package.name)
                        .font(.system(size: 12))
                        .lineLimit(1)
                    Text(package.versionLabel)
                        .font(.system(size: 9))
                        .monospacedDigit()
                        .foregroundStyle(package.isOutdated ? AnyShapeStyle(.orange) : AnyShapeStyle(.tertiary))
                        .lineLimit(1)
                }
                Text(package.summary.isEmpty ? package.kindLabel : package.summary)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 4)

            if package.isInstalled, package.sizeOnDisk > 0 {
                Text(ByteFormat.string(package.sizeOnDisk))
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }

            rowActions(package)
        }
        .opacity(brew.isBusy ? 0.5 : 1)
    }

    @ViewBuilder
    private func rowActions(_ package: BrewPackage) -> some View {
        HStack(spacing: 2) {
            if package.isOutdated, !package.isPinned {
                iconButton("arrow.up.circle.fill", tint: .orange, help: "Update \(package.name)") {
                    pending = .upgrade(package, brew)
                }
            }
            if package.isInstalled {
                iconButton("trash.circle.fill", tint: .secondary, help: "Uninstall \(package.name)") {
                    pending = .uninstall(package, brew)
                }
            } else {
                iconButton("arrow.down.circle.fill", tint: .accentColor, help: "Install \(package.name)") {
                    pending = .install(package, brew)
                }
            }
        }
        .disabled(brew.isBusy)
    }

    private func iconButton(_ symbol: String, tint: Color, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    private var updateAllRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.up.circle")
                .font(.system(size: 11))
                .foregroundStyle(.orange)
                .frame(width: 16)

            Text("\(brew.outdated.count) package\(brew.outdated.count == 1 ? "" : "s") can be updated")
                .font(.system(size: 11))
                .foregroundStyle(.orange)

            Spacer()

            Button {
                pending = .upgradeAll(brew)
            } label: {
                Text("Update all").font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(brew.isBusy)
        }
    }

    // MARK: - Running command

    private func operationBlock(_ operation: BrewOperation) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: operation.phase.iconName)
                    .font(.system(size: 10))
                    .foregroundStyle(.tint)
                Text(operation.title)
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                Button {
                    brew.cancel()
                } label: {
                    Text("Cancel").font(.system(size: 10))
                }
                .buttonStyle(.link)
            }

            // Indeterminate until Homebrew reports a percentage, which it only does
            // while a download is in flight. A bar pinned at zero reads as stuck.
            if let fraction = operation.fraction {
                ProgressView(value: fraction).controlSize(.small)
            } else {
                ProgressView().progressViewStyle(.linear).controlSize(.small)
            }

            Text(operation.lastLine.isEmpty ? operation.phase.rawValue : operation.lastLine)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(8)
        .background(.quaternary.opacity(0.3), in: .rect(cornerRadius: 8))
    }

    // MARK: - Failures

    @ViewBuilder
    private func failureBlock(_ failure: BrewFailure) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            switch failure {
            case .needsTerminal(let command):
                Text("This needs Terminal to ask for the administrator password. DiskPilot never handles passwords.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    brew.continueInTerminal(command)
                } label: {
                    Text("Continue in Terminal").font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

            case .untrustedTap(let tap, let command):
                Text("Homebrew asks you to confirm third-party taps. Trust \(tap) to continue.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    brew.continueInTerminal(command)
                } label: {
                    Text("Review in Terminal").font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

            case .failed(let message):
                Text(message)
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)

            case .cancelled:
                Text("Operation cancelled.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Button {
                brew.dismissFailure()
            } label: {
                Text("Dismiss").font(.system(size: 10))
            }
            .buttonStyle(.link)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.12), in: .rect(cornerRadius: 8))
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if brew.reclaimableBytes > 0 {
                HStack {
                    Text("\(ByteFormat.string(brew.reclaimableBytes)) in old downloads")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                    Spacer()
                    Button {
                        pending = .cleanup(brew)
                    } label: {
                        Text("Reclaim").font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(brew.isBusy)
                }
            }

            HStack(spacing: 10) {
                Button {
                    pending = .updateCatalog(brew)
                } label: {
                    Text("Refresh catalog").font(.system(size: 10))
                }
                .buttonStyle(.link)
                .disabled(brew.isBusy)

                Button {
                    Task { await viewModel.refreshHomebrew(force: true) }
                } label: {
                    Text("Reload list").font(.system(size: 10))
                }
                .buttonStyle(.link)
                .disabled(brew.isBusy || brew.isLoading)

                Spacer()
            }
        }
    }
}

/// A command waiting on confirmation.
///
/// Every one of these changes what is installed on the Mac, and several take
/// minutes, so none of them fire straight from a tap. The closure is built at the
/// point the button is pressed, which keeps the dialog from having to know
/// anything about which package it is talking about.
private struct PendingAction: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let verb: String
    var isDestructive = false
    let run: @MainActor () async -> Void

    static func install(_ package: BrewPackage, _ brew: HomebrewService) -> PendingAction {
        PendingAction(
            title: "Install with Homebrew?",
            message: "Homebrew will download and install \(package.name). Dependencies may also be installed.",
            verb: "Install",
            run: { await brew.install(package) }
        )
    }

    static func uninstall(_ package: BrewPackage, _ brew: HomebrewService) -> PendingAction {
        PendingAction(
            title: "Uninstall with Homebrew?",
            message: "Homebrew will uninstall \(package.name). Configuration files may remain on the system.",
            verb: "Uninstall",
            isDestructive: true,
            run: { await brew.uninstall(package) }
        )
    }

    static func upgrade(_ package: BrewPackage, _ brew: HomebrewService) -> PendingAction {
        PendingAction(
            title: "Update with Homebrew?",
            message: "Homebrew will download and apply the latest version of \(package.name). Dependencies may also be updated.",
            verb: "Update",
            run: { await brew.upgrade(package) }
        )
    }

    static func upgradeAll(_ brew: HomebrewService) -> PendingAction {
        PendingAction(
            title: "Update all with Homebrew?",
            message: "Homebrew will download and apply the latest versions for every package with an update available. Dependencies may also be updated.",
            verb: "Update all",
            run: { await brew.upgradeAll() }
        )
    }

    static func updateCatalog(_ brew: HomebrewService) -> PendingAction {
        PendingAction(
            title: "Refresh the Homebrew catalog?",
            message: "Homebrew will fetch the latest package information and then reload your list.",
            verb: "Refresh",
            run: { await brew.updateCatalog() }
        )
    }

    static func cleanup(_ brew: HomebrewService) -> PendingAction {
        PendingAction(
            title: "Reclaim Homebrew disk space?",
            message: "Runs `brew cleanup -s`: old versions, stale downloads and the download cache. Packages you have installed stay installed.",
            verb: "Reclaim",
            run: { await brew.cleanup() }
        )
    }
}
