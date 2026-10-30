import Foundation
import Network
import Combine

/// Rough network status shown in the window title bar.
enum ConnectionQuality { case good, weak, offline }

/// Watches the network path and publishes the current connection quality.
@MainActor
final class ConnectionMonitor: ObservableObject {
    static let shared = ConnectionMonitor()
    @Published var quality: ConnectionQuality = .good
    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let quality: ConnectionQuality =
                path.status == .satisfied
                ? (path.isExpensive ? .weak : .good)
                : .offline
            Task { @MainActor in self?.quality = quality }
        }
        monitor.start(queue: DispatchQueue(label: "airwave.connection"))
    }
}
