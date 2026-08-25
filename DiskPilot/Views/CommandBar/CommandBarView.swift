//
//  CommandBarView.swift
//  DiskPilot
//

import AppKit
import SwiftUI

struct CommandBarView: View {
    let onExecute: (CommandEntry) -> Void
    let onDismiss: () -> Void
    let onHeightChange: (CGFloat) -> Void

    @State private var query = ""
    @State private var results: [CommandEntry] = []
    @State private var selection = 0
    @FocusState private var isFieldFocused: Bool

    private let rowHeight: CGFloat = 44
    private let fieldHeight: CGFloat = 60

    var body: some View {
        VStack(spacing: 0) {
            field

            if !results.isEmpty {
                Divider()
                list
            }
        }
        .background(.regularMaterial, in: .rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
        .onAppear { refresh() }
        .task {
            // The panel is made key *after* this view is installed in it, and a
            // focus request made before the window is key gets dropped on the
            // floor — which left the bar visibly open but ignoring every keystroke.
            // Asking again on the next runloop pass lands it.
            try? await Task.sleep(for: .milliseconds(60))
            isFieldFocused = true
        }
        .onChange(of: query) { _, _ in refresh() }
        .onChange(of: results.count) { _, _ in reportHeight() }
        // The index is built in the background, so results have to be recomputed
        // when it lands — otherwise the first search shows nothing until you type
        // another character.
        .onChange(of: CommandBarService.shared.indexGeneration) { _, _ in refresh() }
    }

    private var field: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("Search apps, run an action, do maths…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 19))
                .focused($isFieldFocused)
                .onSubmit(executeSelection)
                // Arrow keys must move the list, not the text cursor, so they are
                // intercepted before the field sees them.
                .onKeyPress(.downArrow) { move(by: 1); return .handled }
                .onKeyPress(.upArrow) { move(by: -1); return .handled }
                .onKeyPress(.escape) { onDismiss(); return .handled }
        }
        .padding(.horizontal, 18)
        .frame(height: fieldHeight)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, entry in
                        row(entry, isSelected: index == selection)
                            .id(index)
                            .contentShape(.rect)
                            .onTapGesture {
                                selection = index
                                executeSelection()
                            }
                    }
                }
            }
            .frame(height: listHeight)
            .onChange(of: selection) { _, new in
                withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(new, anchor: .center) }
            }
        }
    }

    private func row(_ entry: CommandEntry, isSelected: Bool) -> some View {
        HStack(spacing: 11) {
            icon(for: entry)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title)
                    .font(.system(size: 14, weight: entry.kind == .math ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(entry.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if isSelected {
                Text("↩")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: rowHeight)
        .background(isSelected ? AnyShapeStyle(.tint.opacity(0.22)) : AnyShapeStyle(.clear))
    }

    @ViewBuilder
    private func icon(for entry: CommandEntry) -> some View {
        if let path = entry.iconPath {
            Image(nsImage: CommandBarService.shared.icon(forApp: path))
                .resizable()
                .frame(width: 22, height: 22)
        } else {
            Image(systemName: entry.kind.iconName)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Behaviour

    private var listHeight: CGFloat {
        min(CGFloat(results.count), 7) * rowHeight
    }

    private func reportHeight() {
        onHeightChange(fieldHeight + (results.isEmpty ? 0 : listHeight + 1))
    }

    private func refresh() {
        results = CommandBarService.shared.results(for: query)
        selection = 0
        reportHeight()
    }

    private func move(by delta: Int) {
        guard !results.isEmpty else { return }
        // Wraps, so holding ↓ at the bottom returns to the top instead of sticking.
        selection = (selection + delta + results.count) % results.count
    }

    private func executeSelection() {
        guard results.indices.contains(selection) else { return }
        onExecute(results[selection])
        query = ""
    }
}
