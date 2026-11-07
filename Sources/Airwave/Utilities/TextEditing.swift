import AppKit

/// Detects when keyboard shortcuts should belong to a text field rather than the app.
@MainActor
enum TextEditing {
    /// Whether the key window's first responder is editing text, so ⌘C, ⌘V and
    /// the arrow-with-⌘ combinations should keep their standard text behaviour.
    static var isEditingText: Bool {
        NSApp.keyWindow?.firstResponder is NSTextView
    }

    /// Sends a standard text action (copy:, paste:, …) to the first responder.
    static func send(_ selector: Selector) {
        NSApp.sendAction(selector, to: nil, from: nil)
    }
}
