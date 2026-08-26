//
//  CleanerSectionView.swift
//  Crest
//

import SwiftUI

/// The cleaner as a single flow: scan, review what was found, move it to the Trash.
/// Everything the user needs to make the decision — what it is, how big, what
/// happens if it goes — is on the same surface as the button that does it.
struct CleanerSectionView: View {
    @Environment(CrestViewModel.self) private var viewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        PanelCard(section: .cleaner) {
            if let scan = viewModel.scan, !scan.isEmpty {
                Text(ByteFormat.string(scan.totalBytes))
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.orange)
            }
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                if viewModel.isScanning {
                    scanningState
                } else if let scan = viewModel.scan {
                    if scan.isEmpty {
                        tidyState
                    } else {
                        results(scan)
                    }
                } else {
                    idleState
                }
            }
        }
    }

    // MARK: - States

    private var idleState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Looks for leftovers from uninstalled apps, caches, logs and developer build output. You review everything before anything moves.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                Task { await viewModel.runScan() }
            } label: {
                Label("Scan", systemImage: "sparkle.magnifyingglass")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .accessibilityLabel("Scan")
        }
    }

    private var scanningState: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: viewModel.scanProgress.fraction)
                .progressViewStyle(.linear)
            HStack {
                Text(viewModel.scanProgress.category?.rawValue ?? viewModel.scanProgress.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(viewModel.scanProgress.fraction * 100))%")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var tidyState: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 1) {
                Text("Nothing to clean")
                    .font(.system(size: 12, weight: .medium))
                Text("Your Mac is tidy.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Scan again") { Task { await viewModel.runScan() } }
                .buttonStyle(.link)
                .font(.system(size: 11))
        }
    }

    @ViewBuilder
    private func results(_ scan: CleanerScanResult) -> some View {
        VStack(spacing: PanelMetrics.rowSpacing) {
            ForEach(scan.presentCategories) { category in
                categoryRow(category, scan: scan)
            }
        }

        if let report = viewModel.lastReport, report.itemsRemoved > 0 {
            Text(report.summary)
                .font(.system(size: 10))
                .foregroundStyle(.green)
        }

        Divider().padding(.vertical, 2)

        HStack(spacing: 8) {
            Button {
                openWindow(id: "review")
            } label: {
                Text("Review…")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel("Review all items")

            Spacer()

            Button {
                Task { await viewModel.removeSelected() }
            } label: {
                if viewModel.isRemoving {
                    ProgressView().controlSize(.small)
                } else {
                    Text(primaryActionTitle)
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(viewModel.selectionIncludesPermanentRemoval ? .red : .accentColor)
            .disabled(viewModel.selectedCount == 0 || viewModel.isRemoving)
            .accessibilityLabel(primaryActionTitle)
        }

        // The consequence of the primary button, stated where the button is. Trash
        // removal is the one irreversible path, so it never hides behind the same
        // wording as everything else.
        Text(viewModel.selectionIncludesPermanentRemoval
             ? "Includes items already in the Trash — those are deleted permanently."
             : "Selected items move to the Trash. You can put them back.")
            .font(.system(size: 10))
            .foregroundStyle(viewModel.selectionIncludesPermanentRemoval ? .orange : .secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var primaryActionTitle: String {
        guard viewModel.selectedCount > 0 else { return "Nothing selected" }
        return "Clean \(ByteFormat.string(viewModel.selectedBytes))"
    }

    // MARK: - Category row

    @ViewBuilder
    private func categoryRow(_ category: CleanerCategory, scan: CleanerScanResult) -> some View {
        let items = scan.items(in: category)
        let isExpanded = viewModel.expandedCategories.contains(category)

        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                PanelCheckbox(state: viewModel.selectionState(for: category), tint: category.accent) {
                    viewModel.toggleCategory(category)
                }

                Button {
                    withAnimation(.snappy(duration: 0.2)) { viewModel.toggleExpanded(category) }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: category.iconName)
                            .font(.system(size: 11))
                            .foregroundStyle(category.accent)
                            .frame(width: 14)
                        Text(category.rawValue)
                            .font(.system(size: 12))
                        Text("\(items.count)")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                        Spacer(minLength: 4)
                        SizeLabel(bytes: scan.bytes(in: category), emphasized: true)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }

            if isExpanded {
                Text(category.blurb)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 22)

                // The panel shows the first few and sends the rest to the review
                // window — a dropdown from the menu bar is the wrong place to
                // scroll through eighty rows.
                VStack(spacing: 3) {
                    ForEach(items.prefix(5)) { item in
                        itemRow(item)
                    }
                    if items.count > 5 {
                        Button {
                            openWindow(id: "review")
                        } label: {
                            Text("\(items.count - 5) more in Review…")
                                .font(.system(size: 10))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.link)
                    }
                }
                .padding(.leading, 22)
            }
        }
    }

    private func itemRow(_ item: CleanableItem) -> some View {
        HStack(spacing: 6) {
            PanelCheckbox(state: viewModel.isSelected(item) ? .all : .none, tint: item.category.accent) {
                viewModel.toggle(item)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(item.name)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let age = item.ageDescription {
                    Text(age)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 4)
            SizeLabel(bytes: item.size)
        }
        .contentShape(.rect)
        .onTapGesture { viewModel.toggle(item) }
    }
}
