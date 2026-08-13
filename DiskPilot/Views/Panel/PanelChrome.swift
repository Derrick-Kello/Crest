//
//  PanelChrome.swift
//  DiskPilot
//

import SwiftUI

enum PanelMetrics {
    static let width: CGFloat = 360
    static let cardRadius: CGFloat = 12
    static let gutter: CGFloat = 12
    static let rowSpacing: CGFloat = 6
}

extension DiskHealthStatus {
    var color: Color {
        switch self {
        case .healthy: .green
        case .moderate: .yellow
        case .critical: .red
        }
    }
}

/// A collapsible card. Each panel section is one of these, so the whole panel
/// reads as a stack of equal-weight things the user can open, close, and ignore.
struct PanelCard<Header: View, Content: View>: View {
    let section: PanelSection
    @ViewBuilder var header: Header
    @ViewBuilder var content: Content

    @Environment(DiskPilotViewModel.self) private var viewModel

    private var isCollapsed: Bool { viewModel.isCollapsed(section) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.22)) {
                    viewModel.toggleCollapsed(section)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: section.iconName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16)

                    Text(section.rawValue)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 8)

                    header

                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, PanelMetrics.gutter)
            .padding(.vertical, 9)
            .accessibilityLabel("\(section.rawValue) section")
            .accessibilityHint(isCollapsed ? "Expand" : "Collapse")

            if !isCollapsed {
                content
                    .padding(.horizontal, PanelMetrics.gutter)
                    .padding(.bottom, PanelMetrics.gutter)
            }
        }
        .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: PanelMetrics.cardRadius))
    }
}

/// Tri-state checkbox. Categories show `.partial` when only some children are
/// ticked, which is the difference between "I chose this" and "the app chose for me".
struct PanelCheckbox: View {
    let state: SelectionState
    var tint: Color = .accentColor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: state.symbolName)
                .font(.system(size: 13))
                .foregroundStyle(state == .none ? AnyShapeStyle(.tertiary) : AnyShapeStyle(tint))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(state == .all ? "Deselect" : "Select")
    }
}

/// The capacity bar. Segments are drawn proportionally with a minimum visible
/// width so a small-but-real slice never vanishes into a hairline.
struct CapacityBar: View {
    struct Segment: Identifiable {
        let id: String
        let bytes: UInt64
        let color: Color
    }

    let total: UInt64
    let segments: [Segment]
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 1) {
                ForEach(segments) { segment in
                    Rectangle()
                        .fill(segment.color)
                        .frame(width: width(for: segment, in: geo.size.width))
                }
                Rectangle().fill(.quaternary)
            }
        }
        .frame(height: height)
        .clipShape(.capsule)
    }

    private func width(for segment: CapacityBar.Segment, in available: CGFloat) -> CGFloat {
        guard total > 0 else { return 0 }
        let raw = available * CGFloat(Double(segment.bytes) / Double(total))
        return segment.bytes > 0 ? max(raw, 3) : 0
    }
}

/// A compact label/value row, used everywhere a section lists a figure.
struct PanelRow<Trailing: View>: View {
    let title: String
    var subtitle: String?
    var iconName: String?
    var iconColor: Color = .secondary
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 8) {
            if let iconName {
                Image(systemName: iconName)
                    .font(.system(size: 11))
                    .foregroundStyle(iconColor)
                    .frame(width: 16)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 6)
            trailing
        }
    }
}

struct SizeLabel: View {
    let bytes: UInt64
    var emphasized = false

    var body: some View {
        Text(ByteFormat.string(bytes))
            .font(.system(size: 11, weight: emphasized ? .semibold : .regular))
            .monospacedDigit()
            .foregroundStyle(emphasized ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
    }
}
