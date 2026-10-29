import SwiftUI
import AppKit
import Network

enum ConnectionQuality { case good, weak, offline }

/// Watches the network path and publishes the current connection quality.
@MainActor
final class ConnectionMonitor: ObservableObject {
    static let shared = ConnectionMonitor()
    @Published var quality: ConnectionQuality = .good
    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let q: ConnectionQuality = path.status == .satisfied
                ? (path.isExpensive ? .weak : .good)
                : .offline
            Task { @MainActor in self?.quality = q }
        }
        monitor.start(queue: DispatchQueue(label: "airwave.connection"))
    }
}

/// Connection quality icon + settings gear for the title-bar row.
struct TitlebarButtons: View {
    @ObservedObject private var conn = ConnectionMonitor.shared
    let openSettings: OpenSettingsAction
    @State private var hovering = false

    private var quality: (label: String, color: Color, symbol: String) {
        switch conn.quality {
        case .good: return ("Connected", .green, "wifi")
        case .weak: return ("Weak connection", .yellow, "wifi.exclamationmark")
        case .offline: return ("No network", .red, "wifi.slash")
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            // Hovering shows the quality immediately as colored text (a native
            // .help tooltip has an uncontrollable delay and cannot be colored).
            Image(systemName: quality.symbol)
                .foregroundStyle(quality.color)
                .onHover { hovering = $0 }
                .popover(isPresented: $hovering, arrowEdge: .bottom) {
                    Text(quality.label)
                        .font(.caption)
                        .foregroundStyle(quality.color)
                        .padding(6)
                }
                .accessibilityLabel(quality.label)
            Button {
                openSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Preferences (⌘,)")
        }
        .controlSize(.small)
        .padding(.trailing, 10)
    }
}

/// Installs the SwiftUI controls in the window's actual title bar. AppKit owns
/// their vertical alignment and keeps them at the trailing edge on resize.
struct TitlebarAccessoryInstaller: NSViewRepresentable {
    @Environment(\.openSettings) private var openSettings

    final class AnchorView: NSView {
        var onWindowChange: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindowChange?(window)
        }
    }

    @MainActor
    final class Coordinator {
        var openSettings: OpenSettingsAction
        private weak var window: NSWindow?
        private var accessory: NSTitlebarAccessoryViewController?
        private var hostingView: NSHostingView<TitlebarButtons>?

        init(openSettings: OpenSettingsAction) {
            self.openSettings = openSettings
        }

        func install(in window: NSWindow) {
            guard self.window !== window || accessory == nil else { return }
            remove()
            // Keep the closed main window available for Dock reopening when quit is disabled.
            window.isReleasedWhenClosed = false

            let hostingView = NSHostingView(rootView: TitlebarButtons(openSettings: openSettings))
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

        func update() {
            hostingView?.rootView = TitlebarButtons(openSettings: openSettings)
        }

        func remove() {
            if let window, let accessory,
               let index = window.titlebarAccessoryViewControllers.firstIndex(where: { $0 === accessory }) {
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
        context.coordinator.openSettings = openSettings
        context.coordinator.update()
    }

    static func dismantleNSView(_ nsView: AnchorView, coordinator: Coordinator) {
        nsView.onWindowChange = nil
        coordinator.remove()
    }
}
