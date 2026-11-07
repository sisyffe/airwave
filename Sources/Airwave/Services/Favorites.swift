import Foundation

struct Favorite: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var url: String
    var thumbnail: Data? = nil
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

    init() {
        let stored = UserDefaultsJSON.load([Favorite].self, from: key) ?? []
        items = ThumbnailCache.canonicalizing(stored, url: \.url, thumbnail: \.thumbnail)
    }

    func add(name: String, url: String, thumbnail: Data? = nil) {
        guard !items.contains(where: { $0.url == url }) else { return }
        items.append(Favorite(name: name.isEmpty ? url : name, url: url, thumbnail: thumbnail))
    }

    /// Store the latest thumbnail for a favorite (refreshed on every play).
    /// Skips favorites with a custom thumbnail so the user's image is kept.
    func setThumbnail(_ data: Data, for url: String) {
        guard let index = items.firstIndex(where: { $0.url == url }) else { return }
        guard items[index].hasCustomThumbnail != true else { return }
        guard let canonical = ThumbnailCache.canonical(data, for: url), items[index].thumbnail != canonical else { return }
        items[index].thumbnail = canonical
    }

    /// Replaces a favorite's artwork with a user-supplied image and marks it
    /// custom, so automatic fetching never overwrites it. Returns the canonical
    /// bytes (for propagating to recents / the player), or nil when the data is
    /// not a decodable image.
    @discardableResult
    func setCustomThumbnail(_ data: Data, for id: Favorite.ID) -> Data? {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        guard let canonical = ThumbnailCache.canonical(data, for: items[index].url) else { return nil }
        items[index].thumbnail = canonical
        items[index].hasCustomThumbnail = true
        return canonical
    }

    /// Clears a custom thumbnail so automatic fetching can resume.
    func clearCustomThumbnail(for id: Favorite.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].thumbnail = nil
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
        UserDefaultsJSON.save(items, to: key)
    }
}
