import AppKit

/// Reads and writes plain text on the general pasteboard.
enum Clipboard {
    /// Replaces the pasteboard contents with `string`.
    static func copy(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    /// The current pasteboard string, if any.
    static var string: String? {
        NSPasteboard.general.string(forType: .string)
    }
}
