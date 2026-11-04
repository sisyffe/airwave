import Foundation

struct Favorite: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var url: String
    /// In-memory canonical bytes, hydrated from `thumbnailKey`. Never persisted
    /// to UserDefaults (see `ThumbnailCache.stripping`).
    var thumbnail: Data? = nil
    /// Content-addressed resource id for the artwork; persisted instead of the
    /// bytes. Owners with identical artwork share the same key.
    var thumbnailKey: String? = nil
    /// Set when the user supplied the artwork themselves. Optional so favorites
    /// stored by older versions (and exported files, which omit it) still decode.
    var hasCustomThumbnail: Bool? = nil
    /// Optional trim offsets applied when playing this favorite's finite track:
    /// `startOffset` is counted from the start, `endOffset` back from the end.
    /// Both nil means the track plays in full.
    var startOffset: TimeInterval? = nil
    var endOffset: TimeInterval? = nil
    /// Learned at playback: true once the URL is known to be a finite track.
    /// Nil while unknown (or live), so the trim UI only shows for finite tracks.
    var isFinite: Bool? = nil
}

@MainActor
final class FavoritesStore: ObservableObject {
    /// Shared instance so the player can resolve a favorite's trim by URL from
    /// any entry point (Favorites, Recents, Dock, hotstart).
    static let shared = FavoritesStore()

    @Published var items: [Favorite] = [] { didSet { save() } }
    private let key = Prefs.favorites
    /// Suppresses saves until the initial load finishes, so hydrating the list
    /// cannot overwrite persisted state.
    private var hasLoaded = false

    init() {
        let stored = UserDefaultsJSON.load([Favorite].self, from: key) ?? []
        items = ThumbnailCache.persisted(
            stored, url: \.url, thumbnail: \.thumbnail, thumbnailKey: \.thumbnailKey)
        hasLoaded = true
    }

    func add(name: String, url: String, thumbnail: Data? = nil) {
        guard !items.contains(where: { $0.url == url }) else { return }
        items.append(Favorite(name: name.isEmpty ? url : name, url: url, thumbnail: thumbnail))
    }

    /// Store the latest thumbnail for every favorite on `url` (refreshed on every
    /// play). Skips favorites with a custom thumbnail so the user's image is kept.
    func setThumbnail(_ data: Data, for url: String) {
        guard let stored = ThumbnailCache.store(data, for: url) else { return }
        applyThumbnail(stored, where: { $0.url == url && $0.hasCustomThumbnail != true })
    }

    /// Store the latest thumbnail for one favorite (automatic fetch when the
    /// playing favorite is known).
    func setThumbnail(_ data: Data, for id: Favorite.ID) {
        guard let stored = ThumbnailCache.store(data, for: items.first { $0.id == id }?.url ?? "") else { return }
        applyThumbnail(stored, where: { $0.id == id && $0.hasCustomThumbnail != true })
    }

    private func applyThumbnail(_ stored: (key: String, data: Data), where matches: (Favorite) -> Bool) {
        var updated = items
        var changed = false
        for index in updated.indices where matches(updated[index]) {
            guard updated[index].thumbnailKey != stored.key else { continue }
            updated[index].thumbnail = stored.data
            updated[index].thumbnailKey = stored.key
            changed = true
        }
        if changed { items = updated }
    }

    /// Replaces a favorite's artwork with a user-supplied image and marks it
    /// custom, so automatic fetching never overwrites it. Returns the canonical
    /// bytes (for propagating to recents / the player), or nil when the data is
    /// not a decodable image.
    @discardableResult
    func setCustomThumbnail(_ data: Data, for id: Favorite.ID) -> Data? {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        guard let stored = ThumbnailCache.store(data, for: items[index].url) else { return nil }
        items[index].thumbnail = stored.data
        items[index].thumbnailKey = stored.key
        items[index].hasCustomThumbnail = true
        return stored.data
    }

    /// Clears a custom thumbnail so automatic fetching can resume.
    func clearCustomThumbnail(for id: Favorite.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].thumbnail = nil
        items[index].thumbnailKey = nil
        items[index].hasCustomThumbnail = nil
    }

    func favorite(for url: String) -> Favorite? { items.first { $0.url == url } }

    /// Records that a URL is a finite track (learned when it is played).
    func setFinite(_ isFinite: Bool, for url: String) {
        guard let index = items.firstIndex(where: { $0.url == url }) else { return }
        guard items[index].isFinite != isFinite else { return }
        items[index].isFinite = isFinite
    }
    func remove(_ favorite: Favorite) { items.removeAll { $0.id == favorite.id } }

    func rename(_ favorite: Favorite, to name: String) {
        guard let index = items.firstIndex(where: { $0.id == favorite.id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        items[index].name = trimmed.isEmpty ? items[index].url : trimmed
    }
    func contains(url: String) -> Bool { items.contains { $0.url == url } }

    private func save() {
        guard hasLoaded else { return }
        UserDefaultsJSON.save(ThumbnailCache.stripping(items, thumbnail: \.thumbnail), to: key)
    }
}
