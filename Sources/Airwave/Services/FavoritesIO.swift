import Foundation

/// Import/export for the favorites list. Exported JSON contains favorite
/// metadata only; thumbnails remain local to the app.
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
            .map { ExportedFavorite(id: $0.id, name: $0.name, url: $0.url) }
        return try encoder.encode(exportItems)
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

    private struct ExportedFavorite: Encodable {
        let id: UUID
        let name: String
        let url: String
    }
}
