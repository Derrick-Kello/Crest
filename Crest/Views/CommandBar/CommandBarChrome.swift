//
//  CommandBarChrome.swift
//  Crest
//

import SwiftUI

/// The look of the command bar, in one place.
///
/// Split out from the view because two things draw it: the bar itself, and the
/// preview in Settings that shows the user what their shortcut opens. A preview
/// that does not match the real thing is worse than no preview, and the only way
/// to be sure it matches is for both to read the same numbers.
enum CommandBarChrome {
    static let cornerRadius: CGFloat = 16
    static let rowRadius: CGFloat = 9
}

/// Glass, and the details that keep it legible in both appearances.
///
/// `glassEffect` gives the refraction and the blur; it does not give a border, and
/// on its own the bar reads as a soft rectangle with no edge. What follows is the
/// edge. A single flat stroke does not work in both appearances — the value that
/// reads as a hairline over a dark desktop disappears entirely over a light one —
/// so the border is a gradient from a bright top edge to a dark bottom one, which
/// is the same trick a physical bevel plays and is why the result reads as a piece
/// of glass sitting above the desktop rather than a shape drawn on it.
///
/// There is no shadow here on purpose. The panel is transparent and AppKit derives
/// its shadow from the alpha of what is drawn, so it already follows this rounded
/// shape — while a SwiftUI shadow would be clipped by the hosting view's bounds,
/// which end exactly at the glass, and show as a hard band down two edges.
///
/// Both appearances are defined explicitly rather than one being derived from the
/// other. The eye is not symmetric about this: in the dark the highlight does the
/// work and the shadow is nearly invisible, and in the light it is the other way
/// round, so the same numbers inverted give a bar that looks right in one and
/// plastic in the other.
struct CommandBarSurface: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    var cornerRadius: CGFloat = CommandBarChrome.cornerRadius

    func body(content: Content) -> some View {
        content
            .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            .overlay {
                // A wash over the glass, to lift the bar off a busy desktop. Kept
                // low in both appearances: it is the material underneath that
                // makes the bar readable, and every point of white added here is a
                // point of contrast taken off the row subtitles drawn on top. At
                // the value this started on, a bar over a bright desktop went pale
                // enough that the secondary text stopped being secondary and
                // started being hard to read.
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(scheme == .dark ? Color.white.opacity(0.03) : Color.white.opacity(0.12))
                    .allowsHitTesting(false)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(borderGradient, lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .top) {
                // The specular line along the top edge. Inset from the corners
                // because a highlight that runs into the curve reads as a seam.
                LinearGradient(
                    colors: [.clear, highlight, .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: 1)
                .padding(.horizontal, cornerRadius)
                .allowsHitTesting(false)
            }
    }

    private var borderGradient: LinearGradient {
        LinearGradient(
            colors: scheme == .dark
                ? [.white.opacity(0.26), .white.opacity(0.08), .white.opacity(0.04)]
                : [.white.opacity(0.95), .white.opacity(0.35), .black.opacity(0.10)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var highlight: Color {
        scheme == .dark ? .white.opacity(0.34) : .white.opacity(0.85)
    }
}

/// The pill behind the selected row.
///
/// Tinted rather than grey, because the accent colour is the only thing on screen
/// that says "this is what ↩ will run", and it has to survive being drawn over a
/// blurred desktop of any colour. It is carried at a lower opacity in the light,
/// where the same value over a bright background reads as a solid block and
/// swallows the row's text.
struct CommandBarSelection: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        RoundedRectangle(cornerRadius: CommandBarChrome.rowRadius)
            .fill(.tint.opacity(scheme == .dark ? 0.30 : 0.20))
            .overlay {
                RoundedRectangle(cornerRadius: CommandBarChrome.rowRadius)
                    .strokeBorder(.tint.opacity(scheme == .dark ? 0.35 : 0.28), lineWidth: 0.5)
            }
    }
}

extension View {
    /// The command bar's glass background, border and shadow.
    func commandBarSurface(cornerRadius: CGFloat = CommandBarChrome.cornerRadius) -> some View {
        modifier(CommandBarSurface(cornerRadius: cornerRadius))
    }
}
