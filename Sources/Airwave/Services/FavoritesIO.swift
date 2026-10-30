import Foundation

/// Lossless import/export for the favorites list. Uses the same JSON shape as
/// the on-disk persistence, so exported files round-trip (thumbnails included).
///
/// Draft favorites with an empty URL are excluded from both export and import,
/// so a file always contains only complete favorites and round-trips cleanly.
enum FavoritesIO {
    static func encode(_ items: [Favorite]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(items.filter { !$0.url.isEmpty })
    }

    static func decode(_ data: Data) throws -> [Favorite] {
        try JSONDecoder().decode([Favorite].self, from: data)
    }

    /// Merges imported favorites into the existing list, skipping URLs that are
    /// already present. Returns the merged list and how many were added.
    static func merge(_ incoming: [Favorite], into existing: [Favorite]) -> (items: [Favorite], added: Int) {
        var merged = existing
        var added = 0
        for favorite in incoming where !favorite.url.isEmpty && !merged.contains(where: { $0.url == favorite.url }) {
            merged.append(favorite)
            added += 1
        }
        return (merged, added)
    }
}
