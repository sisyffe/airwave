import AppKit

/// Opens the Settings window. `showSettingsWindow:` is the only way to open it
/// on macOS 13; macOS 14 has `openSettings`, which SwiftUI views reach through the
/// environment. Callers outside a view use this helper, which covers both.
@MainActor
enum SettingsWindow {
    static func open() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}
