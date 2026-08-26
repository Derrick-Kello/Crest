//
//  PanelChrome.swift
//  Crest
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

/// The body of one tab: a title line carrying the section's headline figure, then
/// its content.
///
/// The tab bar above already says which section you are in, so this exists for the
/// number in the trailing slot — free space, CPU load, battery charge — which is
/// the thing you came to read. The name stays because an icon alone is ambiguous.
struct PanelCard<Header: View, Content: View>: View {
    let section: PanelSection
    @ViewBuilder var header: Header
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(section.rawValue)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                header
            }
            .padding(.horizontal, PanelMetrics.gutter)
            .padding(.top, 10)
            .padding(.bottom, 8)

            content
                .padding(.horizontal, PanelMetrics.gutter)
                .padding(.bottom, PanelMetrics.gutter)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: PanelMetrics.cardRadius))
    }
}

/// Icon tab bar across the top of the panel.
///
/// Icons only: eight labelled tabs will not fit across 360 points without
/// truncating to nonsense, and the section name is repeated immediately below in
/// the card header — so the label is never actually missing, just not duplicated
/// eight times.
struct PanelTabBar: View {
    @Environment(CrestViewModel.self) private var viewModel

    var body: some View {
        HStack(spacing: 2) {
            ForEach(viewModel.visibleSections) { section in
                tab(section)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(.quaternary.opacity(0.28), in: .rect(cornerRadius: 10))
    }

    private func tab(_ section: PanelSection) -> some View {
        let isSelected = viewModel.selectedSection == section

        return Button {
            withAnimation(.snappy(duration: 0.18)) {
                viewModel.select(section)
            }
        } label: {
            Image(systemName: section.iconName)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(maxWidth: .infinity)
                .frame(height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isSelected ? AnyShapeStyle(.tint.opacity(0.16)) : AnyShapeStyle(.clear))
                )
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(section.rawValue)
        .accessibilityLabel(section.rawValue)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
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

/// A row of small figures under a headline. Both voice surfaces use it, and neither
/// should be laying out its own grid to do so.
///
/// Labelled by its label rather than by index, so a figure appearing or disappearing —
/// words-per-minute only exists once something has been dictated — does not make SwiftUI
/// re-identify the ones beside it and cross-fade the wrong numbers.
struct PanelFigureRow: View {
    struct Figure: Identifiable, Hashable {
        let value: String
        let label: String
        var id: String { label }
    }

    let figures: [Figure]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(figures) { figure in
                VStack(spacing: 1) {
                    Text(figure.value)
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(figure.label)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

/// The headline figure at the top of a section: one number worth reading on its own,
/// with the caveat that qualifies it directly underneath.
struct PanelHeadlineFigure: View {
    let symbolName: String
    let value: String
    let caption: String
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbolName)
                .font(.system(size: 15))
                .foregroundStyle(tint)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                Text(caption)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
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
