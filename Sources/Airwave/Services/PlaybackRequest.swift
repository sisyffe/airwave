import Foundation

/// How a link typed into the link field is matched against favorites.
enum ManualLinkBehavior: String {
    case playMatchingFavorite
    case alwaysNew
}

/// Decides which favorite, if any, a manually entered link should play as.
enum ManualLinkRule {
    /// A single favorite with the link is used with its trim. With several, the
    /// first one without a trim is used. Otherwise the link is a new track.
    static func match(url: String, in favorites: [Favorite], behavior: ManualLinkBehavior) -> Favorite? {
        guard behavior == .playMatchingFavorite else { return nil }
        let candidates = favorites.filter { $0.url == url }
        if candidates.count == 1 { return candidates[0] }
        return candidates.first { !$0.isTrimmed }
    }
}

/// Everything the player needs to start a track: its identity, its link and the
/// metadata known before resolution. Favorites, recents, hotstart and the link
/// field all build one of these, so every entry point plays a track the same way.
struct PlaybackRequest: Equatable {
    var trackID: UUID
    var url: String
    var name: String?
    var artworkKey: String?
    var customArtwork: Bool
    var startOffset: TimeInterval?
    var endOffset: TimeInterval?

    init(
        trackID: UUID = UUID(), url: String, name: String? = nil, artworkKey: String? = nil,
        customArtwork: Bool = false, startOffset: TimeInterval? = nil, endOffset: TimeInterval? = nil
    ) {
        self.trackID = trackID
        self.url = url
        self.name = name
        self.artworkKey = artworkKey
        self.customArtwork = customArtwork
        self.startOffset = startOffset
        self.endOffset = endOffset
    }

    init(favorite: Favorite) {
        self.init(
            trackID: favorite.id, url: favorite.url, name: favorite.name, artworkKey: favorite.thumbnailKey,
            customArtwork: favorite.hasCustomThumbnail == true, startOffset: favorite.startOffset,
            endOffset: favorite.endOffset)
    }

    /// A track whose identity is already known (recents, hotstart). A favorite
    /// with the same ID wins, so the track plays with its name and trim.
    static func known(trackID: UUID, url: String, favorites: [Favorite], recents: [RecentTrack]) -> PlaybackRequest {
        if let favorite = favorites.first(where: { $0.id == trackID }) {
            return PlaybackRequest(favorite: favorite)
        }
        let recent = recents.first { $0.id == trackID }
        return PlaybackRequest(
            trackID: trackID, url: url, name: recent?.name, artworkKey: recent?.thumbnailKey,
            customArtwork: recent?.hasCustomThumbnail == true)
    }

    /// A link typed into the link field, matched against favorites per `behavior`.
    static func manual(url: String, favorites: [Favorite], behavior: ManualLinkBehavior) -> PlaybackRequest {
        guard let favorite = ManualLinkRule.match(url: url, in: favorites, behavior: behavior) else {
            return PlaybackRequest(url: url)
        }
        return PlaybackRequest(favorite: favorite)
    }
}
