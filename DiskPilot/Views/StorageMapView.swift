//
//  StorageMapView.swift
//  DiskPilot
//

import SwiftUI

struct StorageMapView: View {
    @Environment(DiskPilotViewModel.self) private var viewModel
    @State private var expandedPaths: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let usage = viewModel.diskUsage {
                    TopFoldersBarChart(directories: usage.topDirectories, limit: 10)
                        .frame(height: 320)

                    Text("Top Folders")
                        .font(.headline)

                    LazyVStack(spacing: 0) {
                        ForEach(Array(usage.topDirectories.prefix(20))) { dir in
                            folderRow(dir)
                            Divider()
                        }
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                } else {
                    ContentUnavailableView("No data", systemImage: "folder")
                }
            }
            .padding(24)
        }
        .navigationTitle("Storage Map")
    }

    private func folderRow(_ dir: DirectoryInfo) -> some View {
        HStack(spacing: 12) {
            Image(systemName: dir.category.iconName)
                .foregroundStyle(dir.category.color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(dir.displayName)
                    .font(.body.weight(.medium))
                Text(dir.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(DiskUsageModel.formatBytes(dir.size))
                .monospacedDigit()
            Text(dir.category.rawValue)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(dir.category.color.opacity(0.15), in: Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            if expandedPaths.contains(dir.path) {
                expandedPaths.remove(dir.path)
            } else {
                expandedPaths.insert(dir.path)
            }
        }
    }
}
