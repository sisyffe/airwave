import AppKit

/// Modal alerts with arbitrary buttons. SwiftUI's `.alert` only supports two or
/// three buttons, so these go through `NSAlert`, which also works on macOS 13.
@MainActor
enum Alerts {
    /// Shows an alert and returns the index of the button pressed, in `buttons` order.
    /// The last button is the cancel button, matching the usual macOS layout.
    static func choose(title: String, message: String, buttons: [String], destructive: Set<Int> = []) -> Int {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        for (index, label) in buttons.enumerated() {
            let button = alert.addButton(withTitle: label)
            if destructive.contains(index) { button.hasDestructiveAction = true }
        }
        let response = alert.runModal()
        return response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
    }
}
