//
//  MenuBarIconLabel.swift
//  Crest
//

import SwiftUI

/// The menu-bar status item: a drive glyph, optionally followed by the free-space
/// figure. The health dot only appears once space is actually tight — a badge that
/// is always lit stops carrying information.
struct MenuBarIconLabel: View {
    @Environment(CrestViewModel.self) private var viewModel

    /// One dot, and disk health owns it.
    ///
    /// There is room for exactly one badge on a fourteen-point glyph, and a full
    /// disk is the more urgent of the two — an update can wait, a Mac with no free
    /// space cannot. The panel's banner says the other thing, and it has room to
    /// say it in words.
    private var badge: Color? {
        if viewModel.health != .healthy { return viewModel.health.color }
        return viewModel.updates.pending == nil ? nil : .accentColor
    }

    var body: some View {
        HStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: viewModel.menuBarIcon.symbolName)
                    .font(.system(size: 14, weight: .medium))

                if let badge {
                    Circle()
                        .fill(badge)
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
        .accessibilityLabel("Crest, \(viewModel.menuBarTitle) free")
    }
}
