import Foundation

struct RecentTrack: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var url: String
    var thumbnail: Data? = nil
}

/// Keeps the last few played tracks so the Dock menu and the in-app Recents
/// list can offer quick play. Backed by UserDefaults, capped at `maxCount`
/// (user-configurable from 1 to 20, defaulting to 5).
@MainActor
final class RecentsStore: ObservableObject {
    static let shared = RecentsStore()

    @Published private(set) var items: [RecentTrack] = [] { didSet { save() } }

    /// User-configurable history size. Persisted and clamped to `Prefs` bounds.
    @Published var maxCount: Int {
        didSet {
            let clamped = min(max(maxCount, Prefs.minRecentMaxCount), Prefs.maxRecentMaxCount)
            if clamped != maxCount { maxCount = clamped; return }
            UserDefaults.standard.set(maxCount, forKey: Prefs.recentMaxCount)
            if items.count > maxCount { items = Array(items.prefix(maxCount)) }
        }
    }

    private let key = Prefs.recentTracks

    private init() {
        let stored = UserDefaults.standard.object(forKey: Prefs.recentMaxCount) as? Int
        maxCount = min(max(stored ?? Prefs.defaultRecentMaxCount, Prefs.minRecentMaxCount), Prefs.maxRecentMaxCount)
        if let decoded = UserDefaultsJSON.load([RecentTrack].self, from: key) {
            items = Array(decoded.prefix(maxCount))
        }
    }

    func record(name: String, url: String, thumbnail: Data? = nil) {
        guard !url.isEmpty else { return }
        var updated = items.filter { $0.url != url }
        let thumb =
            thumbnail.flatMap { ThumbnailCache.canonical($0, for: url) }
            ?? items.first(where: { $0.url == url })?.thumbnail
        updated.insert(RecentTrack(name: name.isEmpty ? url : name, url: url, thumbnail: thumb), at: 0)
        if updated.count > maxCount { updated = Array(updated.prefix(maxCount)) }
        items = updated
    }

    /// Store the latest thumbnail for a recent track (refreshed on every play).
    func setThumbnail(_ data: Data, for url: String) {
        guard let index = items.firstIndex(where: { $0.url == url }) else { return }
        guard let canonical = ThumbnailCache.canonical(data, for: url), items[index].thumbnail != canonical else { return }
        items[index].thumbnail = canonical
    }

    func remove(_ track: RecentTrack) { items.removeAll { $0.id == track.id } }
    func clear() { items = [] }

    private func save() {
        UserDefaultsJSON.save(items, to: key)
    }
}
