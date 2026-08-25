//
//  MenuBarIconLabel.swift
//  DiskPilot
//

import SwiftUI

/// The menu-bar status item: a drive glyph, optionally followed by the free-space
/// figure. The health dot only appears once space is actually tight — a badge that
/// is always lit stops carrying information.
struct MenuBarIconLabel: View {
    @Environment(DiskPilotViewModel.self) private var viewModel

    var body: some View {
        HStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: viewModel.menuBarIcon.symbolName)
                    .font(.system(size: 14, weight: .medium))

                if viewModel.health != .healthy {
                    Circle()
                        .fill(viewModel.health.color)
                        .frame(width: 6, height: 6)
                        .offset(x: 3, y: -2)
                }
            }

            if viewModel.showFreeSpaceInMenuBar, viewModel.volume.totalCapacity > 0 {
                Text(viewModel.menuBarTitle)
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
            }
        }
        .accessibilityLabel("DiskPilot, \(viewModel.menuBarTitle) free")
    }
}
