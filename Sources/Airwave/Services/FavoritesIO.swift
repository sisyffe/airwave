import Foundation

/// Import/export for the favorites list. Exported JSON contains favorite
/// metadata only; thumbnails and internal UUIDs remain local to the app.
///
/// Draft favorites with an empty URL are excluded from both export and import,
/// so a file always contains only complete favorites.
enum FavoritesIO {
    static func encode(_ items: [Favorite]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let exportItems =
            items
            .filter { !$0.url.isEmpty }
            .map {
                ExportedFavorite(
                    name: $0.name, url: $0.url, startOffset: $0.startOffset, endOffset: $0.endOffset)
            }
        return try encoder.encode(exportItems)
    }

    /// Decodes an exported file into fresh favorites. UUIDs are regenerated on
    /// import, so the same file never collides with existing entries.
    static func decode(_ data: Data) throws -> [Favorite] {
        try JSONDecoder().decode([ExportedFavorite].self, from: data).map {
            Favorite(name: $0.name, url: $0.url, startOffset: $0.startOffset, endOffset: $0.endOffset)
        }
    }

    /// Merges imported favorites into the existing list, skipping exact
    /// duplicates (same name, link and trim). Returns the merged list and how
    /// many were added.
    static func merge(_ incoming: [Favorite], into existing: [Favorite]) -> (items: [Favorite], added: Int) {
        var merged = existing
        var identities = Set(existing.map(\.identityKey))
        var names = Set(existing.map(\.name))
        var added = 0
        for favorite in incoming where !favorite.url.isEmpty {
            guard identities.insert(favorite.identityKey).inserted else { continue }
            var favorite = favorite
            favorite.name = FavoriteNaming.unique(favorite.name, url: favorite.url, taken: names)
            names.insert(favorite.name)
            identities.insert(favorite.identityKey)
            merged.append(favorite)
            added += 1
        }
        return (merged, added)
    }

    struct ExportedFavorite: Codable {
        let name: String
        let url: String
        /// Optional trim offsets; omitted from the JSON when unset.
        let startOffset: TimeInterval?
        let endOffset: TimeInterval?
    }
}
