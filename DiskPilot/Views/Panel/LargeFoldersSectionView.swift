//
//  LargeFoldersSectionView.swift
//  DiskPilot
//

import SwiftUI

/// Where the space actually is, for the cases the cleaner deliberately won't touch —
/// Documents, Movies, containers. It points, it doesn't delete: every row opens in
/// Finder so the user decides with their own files in front of them.
struct LargeFoldersSectionView: View {
    @Environment(DiskPilotViewModel.self) private var viewModel

    private var maxSize: UInt64 {
        viewModel.largeFolders.first?.size ?? 1
    }

    var body: some View {
        PanelCard(section: .largeFolders) {
            if viewModel.isLoadingLargeFolders {
                ProgressView().controlSize(.mini)
            }
        } content: {
            VStack(alignment: .leading, spacing: 6) {
                if viewModel.largeFolders.isEmpty {
                    Text("Measures your home folder one level down so you can see which folders carry the weight.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        Task { await viewModel.loadLargeFolders() }
                    } label: {
                        Label("Measure", systemImage: "ruler")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(viewModel.isLoadingLargeFolders)
                } else {
                    ForEach(viewModel.largeFolders.prefix(8)) { folder in
                        folderRow(folder)
                    }

                    Button {
                        Task { await viewModel.loadLargeFolders() }
                    } label: {
                        Text("Measure again")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.link)
                    .disabled(viewModel.isLoadingLargeFolders)
                }
            }
        }
    }

    private func folderRow(_ folder: LargeFolder) -> some View {
        Button {
            viewModel.revealFolder(folder)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(folder.name)
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 4)
                    SizeLabel(bytes: folder.size)
                }
                // A bar relative to the largest folder, so the comparison is visual
                // rather than requiring the user to parse eight byte counts.
                GeometryReader { geo in
                    Capsule()
                        .fill(.tint.opacity(0.5))
                        .frame(width: max(2, geo.size.width * CGFloat(Double(folder.size) / Double(maxSize))))
                }
                .frame(height: 3)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("Reveal \(folder.path) in Finder")
    }
}
