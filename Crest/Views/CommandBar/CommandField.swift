//
//  CommandField.swift
//  Crest
//

import AppKit
import Carbon.HIToolbox
import SwiftUI

/// An `NSTextField` that gets first refusal on key equivalents.
///
/// ⌘↩ and ⌘⇧C never reach `doCommandBy` — the field editor only dispatches
/// unmodified editing commands — so the modified ones have to be caught here,
/// before the window hands them to the menu bar.
final class KeyEquivalentTextField: NSTextField {
    var onKeyEquivalent: ((NSEvent) -> Bool)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if onKeyEquivalent?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }
}

/// The command bar's search field, wrapping `NSTextField` directly.
///
/// A SwiftUI `TextField` looks right here and does not work. Inside an
/// `NSHostingView` in a borderless `NSPanel` it renders every keystroke but never
/// writes them back through its binding, so the query stayed empty while the
/// field showed text — which is why the bar could be typed into and still only
/// ever showed the default list. Measured with a log in the refresh path: one
/// call with an empty query at open, and not one more however much was typed.
///
/// Owning the `NSTextField` fixes that and pays for itself twice over: arrow
/// keys, Return and Escape arrive through `doCommandBy`, which is the field
/// editor's own dispatch and beats `onKeyPress` for reliability.
struct CommandField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    /// Called with -1 for up and +1 for down.
    let onMove: (Int) -> Void
    let onSubmit: () -> Void
    let onCancel: () -> Void
    /// ⌘↩ — show the selected result in Finder.
    var onReveal: () -> Void = {}
    /// ⌘⇧C — copy the selected result's path.
    var onCopyPath: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = KeyEquivalentTextField()
        field.onKeyEquivalent = { [weak coordinator = context.coordinator] event in
            guard let parent = coordinator?.parent else { return false }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            if flags == .command, event.keyCode == UInt16(kVK_Return) {
                parent.onReveal()
                return true
            }
            if flags == [.command, .shift], event.charactersIgnoringModifiers?.lowercased() == "c" {
                parent.onCopyPath()
                return true
            }
            return false
        }
        field.delegate = context.coordinator
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 18, weight: .regular)
        field.placeholderString = placeholder
        field.lineBreakMode = .byTruncatingTail
        field.cell?.usesSingleLineMode = true
        // Continuous, so the binding is written on every keystroke rather than on
        // Return — the whole point of a search field.
        field.cell?.isScrollable = true
        field.isEditable = true
        field.isSelectable = true
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self

        // Only write when they differ. Assigning `stringValue` resets the
        // insertion point, so doing it on every pass would drag the caret back to
        // the start of the line as the user types.
        if field.stringValue != text {
            field.stringValue = text
        }
        context.coordinator.takeFocusIfNeeded(field)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: CommandField
        private var hasFocus = false
        /// Bounded so a panel that never becomes key cannot spin the runloop for
        /// as long as the app is running. Sixty passes is about a second.
        private var attempts = 0

        init(_ parent: CommandField) {
            self.parent = parent
        }

        /// Puts the caret in the field once the panel is actually key.
        ///
        /// A focus request made before the window is key is dropped, which left
        /// the bar open and ignoring every keystroke. Retrying on the next runloop
        /// pass is what lands it.
        func takeFocusIfNeeded(_ field: NSTextField) {
            guard !hasFocus, attempts < 60 else { return }
            attempts += 1

            // The view is laid out before it is in a window, and the window is
            // ordered front before it is key. Both states have to be waited out,
            // and bailing on either was what left the field unfocused — the panel
            // open, the caret absent, and every keystroke going to the app behind.
            if let window = field.window, window.isKeyWindow {
                hasFocus = window.makeFirstResponder(field)
                if hasFocus { return }
            }
            DispatchQueue.main.async { [weak self, weak field] in
                guard let self, let field else { return }
                self.takeFocusIfNeeded(field)
            }
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        /// The field editor's own key dispatch. Arrow keys have to move the result
        /// list rather than the insertion point, and Escape has to close the bar
        /// rather than just clear the field.
        func control(
            _ control: NSControl, textView: NSTextView, doCommandBy selector: Selector
        ) -> Bool {
            switch selector {
            case #selector(NSResponder.moveDown(_:)):
                parent.onMove(1)
            case #selector(NSResponder.moveUp(_:)):
                parent.onMove(-1)
            case #selector(NSResponder.insertNewline(_:)):
                parent.onSubmit()
            case #selector(NSResponder.insertTab(_:)):
                parent.onMove(1)
            case #selector(NSResponder.insertBacktab(_:)):
                parent.onMove(-1)
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
            default:
                return false
            }
            return true
        }
    }
}
