import Foundation

/// Import/export for the favorites list. Exported JSON contains favorite
/// metadata only: no thumbnails and no identifiers. Imported favorites always
/// receive new identifiers.
///
/// Draft favorites with an empty URL are excluded from both export and import,
/// so a file always contains only complete favorites.
enum FavoritesIO {
    enum ImportError: LocalizedError {
        case duplicateNames([String])

        var errorDescription: String? {
            switch self {
            case .duplicateNames(let names):
                return "The file contains favorites with the same name: \(names.joined(separator: ", "))."
            }
        }
    }

    static func encode(_ items: [Favorite]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let exportItems =
            items
            .filter { !$0.url.isEmpty }
            .map {
                ExportedFavorite(name: $0.name, url: $0.url, startOffset: $0.startOffset, endOffset: $0.endOffset)
            }
        return try encoder.encode(exportItems)
    }

    /// Decodes a favorites file into new favorites. Throws when two favorites in
    /// the file share a name, because the whole file is then ambiguous.
    static func decode(_ data: Data) throws -> [Favorite] {
        let imported = try JSONDecoder().decode([ImportedFavorite].self, from: data).filter { !$0.url.isEmpty }
        var seen = Set<String>()
        let duplicates = imported.map(\.name).filter { !seen.insert(Favorite.nameKey($0)).inserted }
        guard duplicates.isEmpty else { throw ImportError.duplicateNames(duplicates) }
        return imported.map {
            Favorite(name: $0.name, url: $0.url, startOffset: $0.startOffset, endOffset: $0.endOffset)
        }
    }

    /// Appends incoming favorites whose names are free, in order. Incoming
    /// favorites whose name is already taken are skipped. Returns the merged list
    /// and the favorites that were added.
    static func merge(_ incoming: [Favorite], into existing: [Favorite]) -> (items: [Favorite], added: [Favorite]) {
        var merged = existing
        var added: [Favorite] = []
        for favorite in incoming where Favorite.isNameAvailable(favorite.name, among: merged) {
            merged.append(favorite)
            added.append(favorite)
        }
        return (merged, added)
    }

    private struct ExportedFavorite: Encodable {
        let name: String
        let url: String
        /// Optional trim offsets; omitted from the JSON when unset.
        let startOffset: TimeInterval?
        let endOffset: TimeInterval?
    }

    /// Reads only the exported fields. Any other key, including a stray `id`, is ignored.
    private struct ImportedFavorite: Decodable {
        let name: String
        let url: String
        let startOffset: TimeInterval?
        let endOffset: TimeInterval?
    }
}
