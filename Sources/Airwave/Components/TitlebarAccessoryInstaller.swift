import SwiftUI
import AppKit

/// Installs the SwiftUI controls in the window's actual title bar. AppKit owns
/// their vertical alignment and keeps them at the trailing edge on resize.
struct TitlebarAccessoryInstaller: NSViewRepresentable {
    let openSettings: () -> Void

    final class AnchorView: NSView {
        var onWindowChange: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindowChange?(window)
        }
    }

    @MainActor
    final class Coordinator {
        private weak var window: NSWindow?
        private var accessory: NSTitlebarAccessoryViewController?
        private var hostingView: NSHostingView<TitlebarButtons>?
        private let openSettings: () -> Void

        init(openSettings: @escaping () -> Void) {
            self.openSettings = openSettings
        }

        /// Attaches the accessory to `window`, moving it if the anchor view was
        /// previously in a different window. Idempotent: re-installing into the
        /// same window keeps the existing accessory instead of adding a second one.
        func install(in window: NSWindow) {
            guard self.window !== window || accessory == nil else { return }
            remove()
            // Keep the closed main window available for Dock reopening when quit is disabled.
            window.isReleasedWhenClosed = false

            let hostingView = NSHostingView(rootView: TitlebarButtons(openSettings: self.openSettings))
            hostingView.sizingOptions = [.intrinsicContentSize]
            hostingView.setFrameSize(hostingView.fittingSize)

            let accessory = NSTitlebarAccessoryViewController()
            accessory.layoutAttribute = .right
            accessory.view = hostingView
            window.addTitlebarAccessoryViewController(accessory)

            self.window = window
            self.accessory = accessory
            self.hostingView = hostingView
        }

        /// Rebuilds the hosted view so it reflects the current environment.
        func update() {
            hostingView?.rootView = TitlebarButtons(openSettings: openSettings)
        }

        /// Detaches the accessory from its window and forgets all references.
        func remove() {
            if let window, let accessory,
                let index = window.titlebarAccessoryViewControllers.firstIndex(where: { $0 === accessory })
            {
                window.removeTitlebarAccessoryViewController(at: index)
            }
            window = nil
            accessory = nil
            hostingView = nil
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(openSettings: openSettings)
    }

    func makeNSView(context: Context) -> AnchorView {
        let view = AnchorView(frame: .zero)
        view.onWindowChange = { [weak coordinator = context.coordinator] window in
            guard let coordinator else { return }
            if let window {
                coordinator.install(in: window)
            } else {
                coordinator.remove()
            }
        }
        return view
    }

    func updateNSView(_ nsView: AnchorView, context: Context) {
        context.coordinator.update()
    }

    static func dismantleNSView(_ nsView: AnchorView, coordinator: Coordinator) {
        nsView.onWindowChange = nil
        coordinator.remove()
    }
}
