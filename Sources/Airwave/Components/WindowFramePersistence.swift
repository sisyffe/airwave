import SwiftUI
import AppKit

/// Applies the "Remember last window position at launch" setting to the window
/// that hosts it. On: AppKit autosaves the frame (size and position). Off: the
/// saved frame is discarded and the window opens at its default size, centered.
struct WindowFramePersistence: NSViewRepresentable {
    let defaultSize: NSSize

    final class AnchorView: NSView {
        var onWindowChange: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindowChange?(window)
        }
    }

    func makeNSView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.onWindowChange = { window in
            guard let window else { return }
            apply(to: window)
        }
        return view
    }

    func updateNSView(_ nsView: AnchorView, context: Context) {}

    private func apply(to window: NSWindow) {
        if Prefs.shouldRememberWindowPosition() {
            window.setFrameAutosaveName(Prefs.mainWindowAutosaveName)
        } else {
            NSWindow.removeFrame(usingName: Prefs.mainWindowAutosaveName)
            window.setFrameAutosaveName("")
            window.setContentSize(defaultSize)
            window.center()
        }
    }
}
