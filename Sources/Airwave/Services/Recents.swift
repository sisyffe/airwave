import Foundation

struct RecentTrack: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var url: String
    var thumbnail: Data? = nil
    /// Set when the artwork was supplied by the user (mirrors the favorite it
    /// was propagated from). Optional so existing recents still decode.
    var hasCustomThumbnail: Bool? = nil
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
            let canonical = ThumbnailCache.canonicalizing(decoded, url: \.url, thumbnail: \.thumbnail)
            items = Array(canonical.prefix(maxCount))
        }
    }

    func record(name: String, url: String, thumbnail: Data? = nil, custom: Bool = false) {
        guard !url.isEmpty else { return }
        let existing = items.first(where: { $0.url == url })
        // A custom cover is sticky: keep it (and its flag) across replays.
        let isCustom = existing?.hasCustomThumbnail == true || custom
        let thumb: Data?
        if existing?.hasCustomThumbnail == true {
            thumb = existing?.thumbnail
        } else {
            thumb = thumbnail.flatMap { ThumbnailCache.canonical($0, for: url) } ?? existing?.thumbnail
        }
        var track = RecentTrack(name: name.isEmpty ? url : name, url: url, thumbnail: thumb)
        track.hasCustomThumbnail = isCustom ? true : nil
        var updated = items.filter { $0.url != url }
        updated.insert(track, at: 0)
        if updated.count > maxCount { updated = Array(updated.prefix(maxCount)) }
        items = updated
    }

    /// Store the latest thumbnail for a recent track (refreshed on every play).
    /// Skips tracks with a custom thumbnail so the user's image is kept.
    func setThumbnail(_ data: Data, for url: String) {
        guard let index = items.firstIndex(where: { $0.url == url }) else { return }
        guard items[index].hasCustomThumbnail != true else { return }
        guard let canonical = ThumbnailCache.canonical(data, for: url), items[index].thumbnail != canonical else { return }
        items[index].thumbnail = canonical
    }

    /// Replaces a recent track's artwork with a user-supplied image. Returns the
    /// canonical bytes, or nil when the URL isn't present or the data isn't an image.
    @discardableResult
    func setCustomThumbnail(_ data: Data, for url: String) -> Data? {
        guard let index = items.firstIndex(where: { $0.url == url }) else { return nil }
        guard let canonical = ThumbnailCache.canonical(data, for: url) else { return nil }
        items[index].thumbnail = canonical
        items[index].hasCustomThumbnail = true
        return canonical
    }

    /// Clears a custom thumbnail so automatic fetching can resume.
    func clearCustomThumbnail(for url: String) {
        guard let index = items.firstIndex(where: { $0.url == url }) else { return }
        items[index].thumbnail = nil
        items[index].hasCustomThumbnail = nil
    }

    func remove(_ track: RecentTrack) { items.removeAll { $0.id == track.id } }
    func clear() { items = [] }

    private func save() {
        UserDefaultsJSON.save(items, to: key)
    }
}
