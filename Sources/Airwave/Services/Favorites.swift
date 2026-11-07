import Foundation

struct Favorite: Identifiable, Codable, Hashable {
    /// Identifies the track everywhere it appears (favorites, recents, the player).
    /// Internal only: never exported.
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

    var isTrimmed: Bool { startOffset != nil || endOffset != nil }

    /// Names are unique case-insensitively, ignoring surrounding whitespace.
    static func nameKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Whether `name` can be used by a favorite, ignoring `id` itself (so a
    /// favorite can keep its own name).
    static func isNameAvailable(_ name: String, among favorites: [Favorite], excluding id: UUID? = nil) -> Bool {
        let key = nameKey(name)
        return !favorites.contains { $0.id != id && nameKey($0.name) == key }
    }
}

@MainActor
final class FavoritesStore: ObservableObject {
    /// Shared instance so the player can resolve a favorite's trim from any
    /// entry point (Favorites, Recents, Dock, hotstart).
    static let shared = FavoritesStore()

    @Published var items: [Favorite] = [] { didSet { save() } }
    private let key = Prefs.favorites

    init() {
        let stored = UserDefaultsJSON.load([Favorite].self, from: key) ?? []
        items = ThumbnailCache.canonicalizing(stored, url: \.url, thumbnail: \.thumbnail)
    }

    func favorite(id: Favorite.ID?) -> Favorite? { items.first { $0.id == id } }

    func isNameAvailable(_ name: String, excluding id: Favorite.ID? = nil) -> Bool {
        Favorite.isNameAvailable(name, among: items, excluding: id)
    }

    /// Adds a favorite under the track's own `id`. Returns false when the name is
    /// taken or the track is already a favorite.
    @discardableResult
    func add(name: String, url: String, thumbnail: Data? = nil, id: UUID = UUID()) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? url : trimmed
        guard favorite(id: id) == nil, isNameAvailable(finalName) else { return false }
        items.append(Favorite(id: id, name: finalName, url: url, thumbnail: thumbnail))
        return true
    }

    /// Store the latest thumbnail for every favorite using `url` (refreshed on every play).
    /// Skips favorites with a custom thumbnail so the user's image is kept.
    func setThumbnail(_ data: Data, for url: String) {
        guard let canonical = ThumbnailCache.canonical(data, for: url) else { return }
        for index in items.indices
        where items[index].url == url && items[index].hasCustomThumbnail != true && items[index].thumbnail != canonical {
            items[index].thumbnail = canonical
        }
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

    /// Records that a URL is a finite track (learned when it is played).
    func setFinite(_ isFinite: Bool, for url: String) {
        for index in items.indices where items[index].url == url && items[index].isFinite != isFinite {
            items[index].isFinite = isFinite
        }
    }

    func remove(_ favorite: Favorite) { items.removeAll { $0.id == favorite.id } }

    /// Renames a favorite. Returns false (and leaves the name unchanged) when the
    /// new name is already used by another favorite. An empty name falls back to the link.
    @discardableResult
    func rename(_ favorite: Favorite, to name: String) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == favorite.id }) else { return false }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? items[index].url : trimmed
        guard isNameAvailable(finalName, excluding: favorite.id) else { return false }
        items[index].name = finalName
        return true
    }

    private func save() {
        UserDefaultsJSON.save(items, to: key)
    }
}
