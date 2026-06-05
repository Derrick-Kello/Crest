//
//  MenuBarIconLabel.swift
//  DiskPilot
//

import SwiftUI

/// Menu bar status item — SF Symbol is reliable; asset image used when present.
struct MenuBarIconLabel: View {
    @Environment(DiskPilotViewModel.self) private var viewModel

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "externaldrive.fill")
                .font(.system(size: 16, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.primary)

            Circle()
                .fill(viewModel.healthStatus.color)
                .frame(width: 7, height: 7)
                .overlay(Circle().strokeBorder(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5))
                .offset(x: 5, y: -5)
        }
        .frame(width: 22, height: 18)
        .help(viewModel.menuBarTitle)
        .accessibilityLabel("DiskPilot, \(viewModel.menuBarTitle)")
    }
}
