import Foundation

struct RecentTrack: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var url: String
}

/// Keeps the last few played tracks so the Dock menu can offer a quick-play
/// submenu. Backed by UserDefaults, capped at `maxCount`.
@MainActor
final class RecentsStore: ObservableObject {
    static let shared = RecentsStore()

    static let maxCount = 5

    @Published private(set) var items: [RecentTrack] = [] { didSet { save() } }
    private let key = Prefs.recentTracks

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([RecentTrack].self, from: data) {
            items = decoded
        }
    }

    func record(name: String, url: String) {
        guard !url.isEmpty else { return }
        var new = items.filter { $0.url != url }
        new.insert(RecentTrack(name: name.isEmpty ? url : name, url: url), at: 0)
        if new.count > Self.maxCount { new = Array(new.prefix(Self.maxCount)) }
        items = new
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
