import Foundation

/// The single representation of a track everywhere in the app: now playing,
/// favorites and recents. `id` is private to the app and never exported.
struct Track: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var url: String
    /// Key of the image in `ThumbnailStore`; the image bytes never live here.
    var thumbnailKey: String? = nil
    var hasCustomThumbnail = false
    /// Learned at playback: nil while unknown. Trim only applies to finite tracks.
    var isFinite: Bool? = nil
    var isDirect = false
    /// Trim offsets: `startOffset` from the start, `endOffset` back from the end.
    /// Kept after a track stops being a favorite, but only editable on favorites.
    var startOffset: TimeInterval? = nil
    var endOffset: TimeInterval? = nil
    var isFavorite = false

    init(name: String, url: String) {
        self.name = name
        self.url = url
    }

    var hasTrim: Bool { (startOffset ?? 0) > 0 || (endOffset ?? 0) > 0 }

    /// Whether both tracks play the same link with the same trim (nil equals 0).
    func playsSameAs(_ other: Track) -> Bool {
        url == other.url && (startOffset ?? 0) == (other.startOffset ?? 0)
            && (endOffset ?? 0) == (other.endOffset ?? 0)
    }
}
