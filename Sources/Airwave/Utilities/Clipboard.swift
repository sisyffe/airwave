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

    /// Image data on the pasteboard (PNG/TIFF or any image `NSImage` can read).
    static var imageData: Data? {
        let pasteboard = NSPasteboard.general
        if let data = pasteboard.data(forType: .png) { return data }
        if let data = pasteboard.data(forType: .tiff) { return data }
        return NSImage(pasteboard: pasteboard)?.tiffRepresentation
    }
}
