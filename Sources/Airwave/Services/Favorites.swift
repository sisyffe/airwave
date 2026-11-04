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

    /// Identity used for import merge and duplicate detection: two favorites are
    /// the same track only when name, link and both trim offsets match. Links
    /// alone may repeat (for example the same song trimmed differently).
    var identityKey: String {
        let start = startOffset.map { String($0) } ?? ""
        let end = endOffset.map { String($0) } ?? ""
        return [name, url, start, end].joined(separator: "\u{1F}")
    }
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
        let hydrated = ThumbnailCache.persisted(
            stored, url: \.url, thumbnail: \.thumbnail, thumbnailKey: \.thumbnailKey)
        items = Self.migrated(hydrated)
        hasLoaded = true
    }

    /// Enforces the name-unique model on stored data: exact duplicates (same
    /// name, link and trim) are merged and remaining duplicate names suffixed.
    private static func migrated(_ items: [Favorite]) -> [Favorite] {
        var result: [Favorite] = []
        var identities = Set<String>()
        var names = Set<String>()
        for var item in items {
            guard identities.insert(item.identityKey).inserted else { continue }
            item.name = FavoriteNaming.unique(item.name, url: item.url, taken: names)
            names.insert(item.name)
            result.append(item)
        }
        return result
    }

    func add(name: String, url: String, thumbnail: Data? = nil) {
        let resolved = FavoriteNaming.unique(name, url: url, taken: Set(items.map(\.name)))
        var favorite = Favorite(name: resolved, url: url)
        if let thumbnail, let stored = ThumbnailCache.store(thumbnail, for: url) {
            favorite.thumbnail = stored.data
            favorite.thumbnailKey = stored.key
        }
        items.append(favorite)
    }

    /// Store the latest thumbnail for every favorite on `url` (refreshed on every
    /// play). Skips favorites with a custom thumbnail so the user's image is kept.
    func setThumbnail(_ data: Data, for url: String) {
        guard let stored = ThumbnailCache.store(data, for: url) else { return }
        applyThumbnail(stored, where: { $0.url == url && $0.hasCustomThumbnail != true })
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

    func favorite(id: Favorite.ID) -> Favorite? { items.first { $0.id == id } }

    /// Records that a URL is a finite track (learned when it is played). Applies
    /// to every favorite on the link, since finiteness is a property of the stream.
    func setFinite(_ isFinite: Bool, for url: String) {
        var updated = items
        var changed = false
        for index in updated.indices where updated[index].url == url && updated[index].isFinite != isFinite {
            updated[index].isFinite = isFinite
            changed = true
        }
        if changed { items = updated }
    }
    func remove(_ favorite: Favorite) { items.removeAll { $0.id == favorite.id } }

    func rename(_ favorite: Favorite, to name: String) {
        commitName(id: favorite.id, name: name)
    }

    /// Commits a name edit, suffixing when another favorite already uses it.
    func commitName(id: Favorite.ID, name: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let taken = Set(items.filter { $0.id != id }.map(\.name))
        items[index].name = FavoriteNaming.unique(name, url: items[index].url, taken: taken)
    }
    func contains(url: String) -> Bool { items.contains { $0.url == url } }

    private func save() {
        guard hasLoaded else { return }
        UserDefaultsJSON.save(ThumbnailCache.stripping(items, thumbnail: \.thumbnail), to: key)
    }
}
