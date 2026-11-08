import Foundation

/// The single store of tracks. Favorites and recents are ordered lists of ids
/// into it, so an edit to a track shows up everywhere at once.
@MainActor
final class TrackLibrary: ObservableObject {
    static let shared = TrackLibrary()

    @Published private(set) var catalog: TrackCatalog { didSet { save() } }

    /// User-configurable history size, clamped to the `Prefs` bounds.
    @Published var maxCount: Int {
        didSet {
            let clamped = min(max(maxCount, Prefs.minRecentMaxCount), Prefs.maxRecentMaxCount)
            if clamped != maxCount { maxCount = clamped; return }
            UserDefaults.standard.set(maxCount, forKey: Prefs.recentMaxCount)
            catalog.applyRecentLimit(maxCount)
        }
    }

    private init() {
        let stored = UserDefaults.standard.object(forKey: Prefs.recentMaxCount) as? Int
        let count = min(max(stored ?? Prefs.defaultRecentMaxCount, Prefs.minRecentMaxCount), Prefs.maxRecentMaxCount)
        var loaded = UserDefaultsJSON.load(TrackCatalog.self, from: Prefs.trackLibrary) ?? TrackCatalog()
        loaded.applyRecentLimit(count)
        maxCount = count
        catalog = loaded
    }

    var favorites: [Track] { catalog.favorites }
    var recents: [Track] { catalog.recents }

    func track(_ id: UUID?) -> Track? { id.flatMap { catalog.tracks[$0] } }
    func isNameTaken(_ name: String, excluding id: UUID? = nil) -> Bool {
        catalog.isNameTaken(name, excluding: id)
    }
    func resolve(url: String) -> Track { catalog.resolve(url: url, mode: Prefs.manualLinkMode()) }

    func recordPlayback(_ track: Track) { catalog.recordPlayback(track) }
    func removeRecent(_ id: UUID) { catalog.removeRecent(id) }
    func clearRecents() { catalog.clearRecents() }

    @discardableResult
    func addFavorite(_ track: Track, name: String) -> Bool { catalog.addFavorite(track, name: name) }
    func addDraft() -> UUID { catalog.addDraft() }
    func removeFavorite(_ id: UUID) { catalog.removeFavorite(id) }
    @discardableResult
    func renameFavorite(_ id: UUID, to name: String) -> Bool { catalog.renameFavorite(id, to: name) }
    func moveFavorites(from source: IndexSet, to destination: Int) {
        catalog.moveFavorites(from: source, to: destination)
    }

    func setTrim(_ id: UUID, start: TimeInterval?, end: TimeInterval?) {
        catalog.setTrim(id, start: start, end: end)
    }
    func setURL(_ id: UUID, to url: String) { catalog.setURL(id, to: url) }
    func setCustomThumbnail(_ id: UUID, key: String) { catalog.setCustomThumbnail(id, key: key) }
    func clearCustomThumbnail(_ id: UUID) { catalog.clearCustomThumbnail(id) }
    func applyThumbnail(_ key: String, forURL url: String) { catalog.applyThumbnail(key, forURL: url) }
    func setFinite(_ id: UUID, _ isFinite: Bool) { catalog.setFinite(id, isFinite) }
    func adoptStationName(_ id: UUID, _ name: String) { catalog.adoptStationName(id, name) }
    func importFavorites(_ incoming: [Track]) -> [UUID] { catalog.importFavorites(incoming) }

    /// Fetches and applies automatic thumbnails for the given tracks.
    func fetchThumbnails(for ids: [UUID]) {
        let links = ids.compactMap { track($0)?.url }
        Task {
            for link in links {
                guard let data = await StreamResolver.thumbnail(for: link), let key = ThumbnailStore.save(data)
                else { continue }
                applyThumbnail(key, forURL: link)
            }
        }
    }

    /// Thumbnail keys to keep, including the hotstart track's.
    var keptThumbnailKeys: Set<String> {
        var keys = catalog.referencedThumbnailKeys
        if let last = UserDefaultsJSON.load(Track.self, from: Prefs.lastTrack)?.thumbnailKey { keys.insert(last) }
        return keys
    }

    private func save() { UserDefaultsJSON.save(catalog, to: Prefs.trackLibrary) }
}
