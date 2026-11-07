import Foundation

struct RecentTrack: Codable, Hashable, Identifiable {
    /// The identity of the track that was played (shared with a favorite when it was played as one).
    var id = UUID()
    var name: String
    var url: String
    /// Key of the artwork in `ThumbnailCache`. Nil when there is none.
    var thumbnailKey: String? = nil
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
            items = Array(decoded.prefix(maxCount))
        }
    }

    /// Records a play of `trackID`. Entries are deduplicated by track identity,
    /// so the same link played as two different tracks appears twice.
    func record(trackID: UUID, name: String, url: String, thumbnailKey: String? = nil, custom: Bool = false) {
        guard !url.isEmpty else { return }
        let existing = items.first { $0.id == trackID }
        // A custom cover is sticky: keep it (and its flag) across replays.
        let isCustom = existing?.hasCustomThumbnail == true || custom
        let key = existing?.hasCustomThumbnail == true ? existing?.thumbnailKey : (thumbnailKey ?? existing?.thumbnailKey)
        var track = RecentTrack(id: trackID, name: name.isEmpty ? url : name, url: url, thumbnailKey: key)
        track.hasCustomThumbnail = isCustom ? true : nil
        var updated = items.filter { $0.id != trackID }
        updated.insert(track, at: 0)
        if updated.count > maxCount { updated = Array(updated.prefix(maxCount)) }
        items = updated
    }

    /// Store the latest thumbnail for every recent entry using `url` (refreshed on every play).
    /// Skips entries with a custom thumbnail so the user's image is kept.
    func setThumbnailKey(_ key: String, for url: String) {
        for index in items.indices where items[index].url == url && items[index].hasCustomThumbnail != true {
            items[index].thumbnailKey = key
        }
    }

    /// Marks a recent track's artwork as user-supplied; `key` is already stored in `ThumbnailCache`.
    func setCustomThumbnailKey(_ key: String, for id: RecentTrack.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].thumbnailKey = key
        items[index].hasCustomThumbnail = true
    }

    /// Clears a custom thumbnail so automatic fetching can resume.
    func clearCustomThumbnail(for id: RecentTrack.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].thumbnailKey = nil
        items[index].hasCustomThumbnail = nil
    }

    var thumbnailKeys: Set<String> { Set(items.compactMap(\.thumbnailKey)) }

    func remove(_ track: RecentTrack) { items.removeAll { $0.id == track.id } }
    func clear() { items = [] }

    private func save() {
        UserDefaultsJSON.save(items, to: key)
    }
}
