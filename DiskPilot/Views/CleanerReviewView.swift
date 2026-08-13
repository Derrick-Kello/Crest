//
//  CleanerReviewView.swift
//  DiskPilot
//

import SwiftUI

/// The full review list, in a real window because this is the one task that needs
/// room: every item found, grouped, sortable by size, with the path visible and a
/// way to open any row in Finder before deciding.
struct CleanerReviewView: View {
    @Environment(DiskPilotViewModel.self) private var viewModel
    @State private var searchText = ""
    @State private var categoryFilter: CleanerCategory?

    private var scan: CleanerScanResult? { viewModel.scan }

    private var visibleItems: [CleanableItem] {
        guard let scan else { return [] }
        return scan.items.filter { item in
            if let categoryFilter, item.category != categoryFilter { return false }
            guard !searchText.isEmpty else { return true }
            return item.name.localizedCaseInsensitiveContains(searchText)
                || item.detail.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let scan, !scan.isEmpty {
                filterBar(scan)
                Divider()
                list
                Divider()
                actionBar
            } else {
                ContentUnavailableView(
                    scan == nil ? "No scan yet" : "Nothing to clean",
                    systemImage: scan == nil ? "sparkle.magnifyingglass" : "checkmark.seal",
                    description: Text(scan == nil
                        ? "Run a scan from the menu bar panel to see what can be removed."
                        : "Your Mac is tidy.")
                )
            }
        }
        .frame(minWidth: 620, minHeight: 460)
        .navigationTitle("Review")
    }

    // MARK: - Filter bar

    private func filterBar(_ scan: CleanerScanResult) -> some View {
        HStack(spacing: 10) {
            Picker("", selection: $categoryFilter) {
                Text("All categories").tag(CleanerCategory?.none)
                ForEach(scan.presentCategories) { category in
                    Text("\(category.rawValue) — \(ByteFormat.string(scan.bytes(in: category)))")
                        .tag(CleanerCategory?.some(category))
                }
            }
            .labelsHidden()
            .frame(width: 260)

            TextField("Filter", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 220)

            Spacer()

            Text("\(visibleItems.count) items")
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - List

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(visibleItems) { item in
                    row(item)
                    Divider().padding(.leading, 40)
                }
            }
        }
    }

    private func row(_ item: CleanableItem) -> some View {
        HStack(spacing: 10) {
            PanelCheckbox(state: viewModel.isSelected(item) ? .all : .none, tint: item.category.accent) {
                viewModel.toggle(item)
            }
            .padding(.leading, 14)

            Image(systemName: item.category.iconName)
                .font(.system(size: 12))
                .foregroundStyle(item.category.accent)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 13))
                HStack(spacing: 6) {
                    Text(item.category.rawValue)
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(item.category.accent.opacity(0.15), in: .capsule)
                    Text(item.url.path)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 8)

            if let age = item.ageDescription {
                Text(age)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            Text(item.formattedSize)
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .frame(width: 78, alignment: .trailing)

            Button {
                viewModel.revealInFinder(item)
            } label: {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Reveal in Finder")
            .padding(.trailing, 14)
        }
        .padding(.vertical, 7)
        .contentShape(.rect)
        .onTapGesture { viewModel.toggle(item) }
    }

    // MARK: - Actions

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button("Select all shown") {
                viewModel.selectedItemIDs.formUnion(visibleItems.map(\.id))
            }
            .controlSize(.small)

            Button("Deselect all") {
                viewModel.selectedItemIDs.subtract(visibleItems.map(\.id))
            }
            .controlSize(.small)

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                Text("\(viewModel.selectedCount) selected — \(ByteFormat.string(viewModel.selectedBytes))")
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                Text(viewModel.selectionIncludesPermanentRemoval
                     ? "Trash items are deleted permanently"
                     : "Moves to the Trash — reversible")
                    .font(.system(size: 10))
                    .foregroundStyle(viewModel.selectionIncludesPermanentRemoval ? .orange : .secondary)
            }

            Button {
                Task { await viewModel.removeSelected() }
            } label: {
                if viewModel.isRemoving {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Clean")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(viewModel.selectionIncludesPermanentRemoval ? .red : .accentColor)
            .disabled(viewModel.selectedCount == 0 || viewModel.isRemoving)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
