//
//  UninstallerView.swift
//  DiskPilot
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Removes an app together with the support files, preferences, caches and
/// startup items it leaves behind.
///
/// A window rather than a panel section, for the same reason the cleaner review
/// is one: the decision needs every path visible at once. Dragging the app in is
/// the fastest route and the one people reach for, so the drop zone is the first
/// thing in the window — but it is never the only route, because a drop target
/// alone is invisible to anyone using the keyboard.
struct UninstallerView: View {
    @Environment(DiskPilotViewModel.self) private var viewModel

    @State private var appQuery = ""
    @State private var isDropTargeted = false
    @State private var confirmRemoval = false

    var body: some View {
        VStack(spacing: 0) {
            if let report = viewModel.uninstallReport {
                doneState(report)
            } else if let scan = viewModel.uninstallScan {
                resultHeader(scan)
                Divider()
                resultList(scan)
                Divider()
                actionBar(scan)
            } else if viewModel.isScanningApp {
                scanningState
            } else {
                chooser
            }
        }
        .frame(minWidth: 620, minHeight: 480)
        .navigationTitle("Uninstall an app")
        .confirmationDialog(
            "Move \(viewModel.uninstallSelectionCount) item\(viewModel.uninstallSelectionCount == 1 ? "" : "s") to the Trash?",
            isPresented: $confirmRemoval,
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                Task { await viewModel.performUninstall() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Nothing is deleted permanently. \(viewModel.uninstallTargetName) quits first if it is running, so it cannot write its preferences back.")
        }
    }

    // MARK: - Choosing an app

    private var chooser: some View {
        VStack(spacing: 0) {
            dropZone
                .padding(20)

            Divider()

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                TextField("Search installed apps", text: $appQuery)
                    .textFieldStyle(.plain)
                Spacer()
                Text("\(filteredApps.count) apps")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredApps) { app in
                        appRow(app)
                        Divider().padding(.leading, 46)
                    }
                }
            }
        }
        .task { viewModel.commandBar.buildIndex() }
    }

    private var filteredApps: [IndexedApp] {
        let trimmed = appQuery.trimmingCharacters(in: .whitespaces).lowercased()
        let apps = viewModel.commandBar.apps
        guard !trimmed.isEmpty else { return apps }
        return apps
            .compactMap { app -> (IndexedApp, Int)? in
                guard let score = AppIndex.score(query: trimmed, candidate: app.lowercaseName, initials: app.initials) else { return nil }
                return (app, score)
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    private var dropZone: some View {
        VStack(spacing: 8) {
            Image(systemName: "trash.square")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(isDropTargeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            Text("Drag an app here")
                .font(.headline)
            Text("or choose one below. Nothing is removed without your confirmation.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isDropTargeted ? AnyShapeStyle(.tint.opacity(0.1)) : AnyShapeStyle(.quaternary.opacity(0.25)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isDropTargeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                )
        )
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url, url.pathExtension == "app" else { return }
                Task { @MainActor in await viewModel.chooseAppToUninstall(at: url) }
            }
            return true
        }
    }

    private func appRow(_ app: IndexedApp) -> some View {
        Button {
            Task { await viewModel.chooseAppToUninstall(at: URL(fileURLWithPath: app.path)) }
        } label: {
            HStack(spacing: 10) {
                Image(nsImage: viewModel.commandBar.icon(forApp: app.path))
                    .resizable()
                    .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name)
                        .font(.system(size: 13))
                    Text(app.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Scanning

    private var scanningState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Scanning files")
                .font(.headline)
            Text("Looking through Application Support, Preferences, Containers, Caches, Logs and startup items.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Results

    private func resultHeader(_ scan: UninstallScan) -> some View {
        HStack(spacing: 12) {
            Image(nsImage: viewModel.commandBar.icon(forApp: scan.target.url.path))
                .resizable()
                .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(scan.target.name)
                    .font(.system(size: 15, weight: .semibold))
                Text([scan.target.version.map { "Version \($0)" }, scan.target.bundleIdentifier]
                    .compactMap { $0 }
                    .joined(separator: " — "))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(ByteFormat.string(scan.totalBytes))
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                Text("\(scan.items.count) item\(scan.items.count == 1 ? "" : "s") found")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Button("Choose another") {
                viewModel.resetUninstaller()
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func resultList(_ scan: UninstallScan) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(scan.presentCategories) { category in
                    categoryHeader(scan, category)
                    ForEach(scan.items(in: category)) { item in
                        itemRow(item)
                        Divider().padding(.leading, 44)
                    }
                }
            }
        }
    }

    private func categoryHeader(_ scan: UninstallScan, _ category: LeftoverCategory) -> some View {
        let items = scan.items(in: category)
        let bytes = items.reduce(UInt64(0)) { $0 + $1.size }

        return HStack(spacing: 8) {
            PanelCheckbox(state: viewModel.leftoverSelectionState(for: category), tint: category.accent) {
                viewModel.toggleLeftoverCategory(category)
            }
            Image(systemName: category.iconName)
                .font(.system(size: 11))
                .foregroundStyle(category.accent)
                .frame(width: 16)
            Text(category.rawValue)
                .font(.system(size: 12, weight: .semibold))
            Text("\(items.count)")
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(category.accent.opacity(0.15), in: .capsule)
            Spacer()
            Text(ByteFormat.string(bytes))
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    private func itemRow(_ item: LeftoverItem) -> some View {
        HStack(spacing: 10) {
            PanelCheckbox(state: viewModel.isLeftoverSelected(item) ? .all : .none, tint: item.category.accent) {
                viewModel.toggleLeftover(item)
            }
            .padding(.leading, 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 5) {
                    Text(item.location)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if item.needsAdmin {
                        Text("needs admin")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.orange)
                    }
                }
            }

            Spacer(minLength: 8)

            Text(item.formattedSize)
                .font(.system(size: 11))
                .monospacedDigit()
                .frame(width: 72, alignment: .trailing)
                .foregroundStyle(.secondary)

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            } label: {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Reveal in Finder")
            .padding(.trailing, 16)
        }
        .padding(.vertical, 5)
        .contentShape(.rect)
        .onTapGesture { viewModel.toggleLeftover(item) }
    }

    private func actionBar(_ scan: UninstallScan) -> some View {
        HStack(spacing: 10) {
            Button("Select all") {
                viewModel.uninstallSelection = Set(scan.items.map(\.id))
            }
            .controlSize(.small)

            Button("Deselect all") {
                viewModel.uninstallSelection = []
            }
            .controlSize(.small)

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                Text("\(viewModel.uninstallSelectionCount) of \(scan.items.count) selected — \(ByteFormat.string(viewModel.uninstallSelectedBytes))")
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                Text("Everything moves to the Trash — reversible")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Button {
                confirmRemoval = true
            } label: {
                if viewModel.isUninstalling {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Move to Trash")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(viewModel.uninstallSelectionCount == 0 || viewModel.isUninstalling)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Done

    private func doneState(_ report: UninstallReport) -> some View {
        VStack(spacing: 14) {
            Image(systemName: report.failures.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 38))
                .foregroundStyle(report.failures.isEmpty ? .green : .orange)

            Text(report.summary)
                .font(.headline)
                .multilineTextAlignment(.center)

            if !report.failures.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(report.failures.prefix(5), id: \.self) { failure in
                        Text(failure)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: 420, alignment: .leading)
            }

            HStack(spacing: 10) {
                Button("Open Trash") {
                    NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appending(path: ".Trash"))
                }
                Button("Uninstall another") {
                    viewModel.resetUninstaller()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
