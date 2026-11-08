import Foundation

/// How a link typed by hand is matched against known tracks.
enum ManualLinkMode: String, CaseIterable {
    /// Always picks an existing track with the same link when there is one.
    case matchesClosest
    /// Only reuses a track with the same link and no trim.
    case exactlyMatches
    /// Ignores favorites and recents: always a new track.
    case alwaysNew

    static let defaultMode = ManualLinkMode.exactlyMatches
}

/// Every known track plus the ordered favorites and recents lists that refer
/// to them by id. Pure value logic so it can be smoke-tested.
struct TrackCatalog: Codable, Equatable {
    var tracks: [UUID: Track] = [:]
    var favoriteOrder: [UUID] = []
    var recentOrder: [UUID] = []
    var recentLimit = 5

    static let defaultDraftName = "New Favorite"

    var favorites: [Track] { favoriteOrder.compactMap { tracks[$0] } }
    var recents: [Track] { recentOrder.compactMap { tracks[$0] } }

    var referencedThumbnailKeys: Set<String> { Set(tracks.values.compactMap(\.thumbnailKey)) }

    // MARK: Names

    /// Trimmed, whitespace-collapsed, case-insensitive form used to compare names.
    static func nameKey(_ name: String) -> String {
        name.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }

    /// Whether another favorite already uses `name`.
    func isNameTaken(_ name: String, excluding id: UUID? = nil) -> Bool {
        let key = Self.nameKey(name)
        return favorites.contains { $0.id != id && Self.nameKey($0.name) == key }
    }

    /// `base`, or `base` plus the first free counter formatted by `suffix`.
    func uniqueName(_ base: String, suffix: (Int) -> String) -> String {
        var candidate = base
        var counter = 2
        while isNameTaken(candidate) {
            candidate = base + suffix(counter)
            counter += 1
        }
        return candidate
    }

    // MARK: Resolution

    /// The track to play for a link typed by hand. Returns a new, unstored
    /// track when nothing qualifies.
    func resolve(url: String, mode: ManualLinkMode) -> Track {
        let sameLinkFavorites = favorites.filter { $0.url == url }
        let sameLinkRecents = recents.filter { $0.url == url }
        let found: Track?
        switch mode {
        case .matchesClosest:
            found =
                sameLinkFavorites.first { !$0.hasTrim } ?? sameLinkFavorites.first
                ?? sameLinkRecents.first { !$0.hasTrim } ?? sameLinkRecents.first
        case .exactlyMatches:
            found = (sameLinkFavorites + sameLinkRecents).first { !$0.hasTrim }
        case .alwaysNew:
            found = nil
        }
        return found ?? Track(name: url, url: url)
    }

    // MARK: Recents

    /// Stores a played track and moves it to the front of recents. A stored
    /// track keeps its name (favorites), trim and cover; playback only refreshes
    /// what it learns about the stream.
    mutating func recordPlayback(_ played: Track) {
        if var stored = tracks[played.id] {
            if !stored.isFavorite { stored.name = played.name }
            if let isFinite = played.isFinite { stored.isFinite = isFinite }
            stored.isDirect = played.isDirect
            tracks[played.id] = stored
        } else {
            var added = played
            added.isFavorite = false
            tracks[played.id] = added
        }
        recentOrder.removeAll { $0 == played.id }
        recentOrder.insert(played.id, at: 0)
        trimRecents()
    }

    mutating func applyRecentLimit(_ limit: Int) {
        recentLimit = limit
        trimRecents()
    }

    mutating func removeRecent(_ id: UUID) {
        recentOrder.removeAll { $0 == id }
        collectGarbage()
    }

    mutating func clearRecents() {
        recentOrder = []
        collectGarbage()
    }

    private mutating func trimRecents() {
        if recentOrder.count > recentLimit { recentOrder = Array(recentOrder.prefix(recentLimit)) }
        collectGarbage()
    }

    /// Drops tracks that are neither favorites nor recents.
    private mutating func collectGarbage() {
        let kept = Set(favoriteOrder).union(recentOrder)
        tracks = tracks.filter { kept.contains($0.key) }
    }

    // MARK: Favorites

    /// Makes `track` a favorite, keeping its identity. False when the name is taken.
    @discardableResult
    mutating func addFavorite(_ track: Track, name: String) -> Bool {
        let collapsed = name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let finalName = collapsed.isEmpty ? track.url : collapsed
        guard !isNameTaken(finalName, excluding: track.id) else { return false }
        var favorite = tracks[track.id] ?? track
        if favorite.isFinite == nil { favorite.isFinite = track.isFinite }
        favorite.name = finalName
        favorite.isFavorite = true
        tracks[track.id] = favorite
        if !favoriteOrder.contains(track.id) { favoriteOrder.append(track.id) }
        return true
    }

    /// Creates an empty favorite to be filled in from Settings.
    mutating func addDraft() -> UUID {
        var draft = Track(name: uniqueName(Self.defaultDraftName) { " \($0)" }, url: "")
        draft.isFavorite = true
        tracks[draft.id] = draft
        favoriteOrder.append(draft.id)
        return draft.id
    }

    /// Stops a track being a favorite. It keeps its metadata only while it is in
    /// recents; otherwise it is forgotten.
    mutating func removeFavorite(_ id: UUID) {
        guard tracks[id] != nil else { return }
        favoriteOrder.removeAll { $0 == id }
        tracks[id]?.isFavorite = false
        collectGarbage()
    }

    @discardableResult
    mutating func renameFavorite(_ id: UUID, to name: String) -> Bool {
        guard var track = tracks[id], track.isFavorite else { return false }
        let collapsed = name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let finalName = collapsed.isEmpty ? track.url : collapsed
        guard !isNameTaken(finalName, excluding: id) else { return false }
        track.name = finalName
        tracks[id] = track
        return true
    }

    mutating func moveFavorites(from source: IndexSet, to destination: Int) {
        let moving = source.map { favoriteOrder[$0] }
        let removedBefore = source.filter { $0 < destination }.count
        var rest = favoriteOrder
        for index in source.reversed() { rest.remove(at: index) }
        rest.insert(contentsOf: moving, at: destination - removedBefore)
        favoriteOrder = rest
    }

    // MARK: Favorite-only edits

    mutating func setTrim(_ id: UUID, start: TimeInterval?, end: TimeInterval?) {
        guard var track = tracks[id], track.isFavorite else { return }
        track.startOffset = (start ?? 0) > 0 ? start : nil
        track.endOffset = (end ?? 0) > 0 ? end : nil
        tracks[id] = track
    }

    mutating func setURL(_ id: UUID, to url: String) {
        guard var track = tracks[id], track.isFavorite, track.url != url else { return }
        track.url = url
        track.isFinite = nil
        if !track.hasCustomThumbnail { track.thumbnailKey = nil }
        tracks[id] = track
    }

    mutating func setCustomThumbnail(_ id: UUID, key: String) {
        guard var track = tracks[id], track.isFavorite else { return }
        track.thumbnailKey = key
        track.hasCustomThumbnail = true
        tracks[id] = track
    }

    mutating func clearCustomThumbnail(_ id: UUID) {
        guard var track = tracks[id], track.isFavorite else { return }
        track.thumbnailKey = nil
        track.hasCustomThumbnail = false
        tracks[id] = track
    }

    // MARK: Playback-derived updates

    /// Sets an automatic thumbnail on every track with this link, except custom covers.
    mutating func applyThumbnail(_ key: String, forURL url: String) {
        for (id, var track) in tracks where track.url == url && !track.hasCustomThumbnail {
            guard track.thumbnailKey != key else { continue }
            track.thumbnailKey = key
            tracks[id] = track
        }
    }

    mutating func setFinite(_ id: UUID, _ isFinite: Bool) {
        guard tracks[id]?.isFinite != isFinite else { return }
        tracks[id]?.isFinite = isFinite
    }

    /// A non-favorite still named after its link adopts the station name.
    mutating func adoptStationName(_ id: UUID, _ name: String) {
        guard let track = tracks[id], !track.isFavorite, track.name == track.url else { return }
        tracks[id]?.name = name
    }

    // MARK: Import

    /// Adds imported tracks as new favorites with fresh identities, suffixing
    /// names that clash. Returns the new ids.
    mutating func importFavorites(_ incoming: [Track]) -> [UUID] {
        var added: [UUID] = []
        for source in incoming where !source.url.isEmpty {
            var favorite = Track(name: source.name, url: source.url)
            favorite.startOffset = source.startOffset
            favorite.endOffset = source.endOffset
            favorite.isFavorite = true
            let base = favorite.name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            favorite.name = uniqueName(base.isEmpty ? source.url : base) { " \($0)" }
            tracks[favorite.id] = favorite
            favoriteOrder.append(favorite.id)
            added.append(favorite.id)
        }
        return added
    }
}
