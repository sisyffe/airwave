import AppKit

/// Canonical source of thumbnail images shared by the favorites and recents
/// stores.
///
/// Both stores hold a `thumbnail` field so the persisted JSON stays unchanged,
/// but every thumbnail is downscaled through this type first. That keeps the
/// bytes for a given link identical everywhere instead of each store picking
/// its own size.
@MainActor
enum ThumbnailCache {
    /// Longest side of a stored thumbnail, in points.
    nonisolated static let maxSide: CGFloat = 256

    private struct Entry {
        let source: Data
        let thumbnail: Data
    }

    private static var entries: [String: Entry] = [:]

    /// Returns the canonical thumbnail for `url`, downscaling `data` when needed.
    ///
    /// Recomputes when `data` differs from the last source seen for `url`, so a
    /// refreshed cover is never masked by a stale cache entry. Returns nil when
    /// `data` is not a decodable image.
    static func canonical(_ data: Data, for url: String) -> Data? {
        if let entry = entries[url], entry.source == data { return entry.thumbnail }
        guard let image = NSImage(data: data), let downscaled = image.downsized(maxSide: maxSide) else {
            return nil
        }
        entries[url] = Entry(source: data, thumbnail: downscaled)
        return downscaled
    }
}
