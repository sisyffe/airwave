import Foundation
import AppKit

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
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([RecentTrack].self, from: data) {
            items = Array(decoded.prefix(maxCount))
        }
    }

    func record(name: String, url: String, thumbnail: Data? = nil) {
        guard !url.isEmpty else { return }
        var new = items.filter { $0.url != url }
        let thumb = thumbnail ?? smallThumbnail(for: url)
        new.insert(RecentTrack(name: name.isEmpty ? url : name, url: url, thumbnail: thumb), at: 0)
        if new.count > maxCount { new = Array(new.prefix(maxCount)) }
        items = new
    }

    /// Store the latest (downscaled) thumbnail for a recent track.
    func setThumbnail(_ data: Data, for url: String) {
        guard let i = items.firstIndex(where: { $0.url == url }) else { return }
        let small = NSImage(data: data).flatMap { $0.downsized(maxSide: 96) } ?? data
        guard items[i].thumbnail != small else { return }
        items[i].thumbnail = small
    }

    func remove(_ track: RecentTrack) { items.removeAll { $0.id == track.id } }
    func clear() { items = [] }

    /// A previously-known thumbnail for the same URL, downscaled for compact storage.
    private func smallThumbnail(for url: String) -> Data? {
        guard let data = items.first(where: { $0.url == url })?.thumbnail else { return nil }
        guard let img = NSImage(data: data) else { return data }
        return img.downsized(maxSide: 96) ?? data
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
