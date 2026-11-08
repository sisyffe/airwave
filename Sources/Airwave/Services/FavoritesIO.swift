import Foundation

/// Import/export for the favorites list. Files hold names, links and trims
/// only: no identities, thumbnails or flags. Drafts with an empty link are
/// excluded on both export and import.
enum FavoritesIO {
    private struct Entry: Codable {
        let name: String
        let url: String
        let startOffset: TimeInterval?
        let endOffset: TimeInterval?
    }

    static func encode(_ favorites: [Track]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let entries =
            favorites
            .filter { !$0.url.isEmpty }
            .map { Entry(name: $0.name, url: $0.url, startOffset: $0.startOffset, endOffset: $0.endOffset) }
        return try encoder.encode(entries)
    }

    /// Decodes into tracks with brand-new identities.
    static func decode(_ data: Data) throws -> [Track] {
        try JSONDecoder().decode([Entry].self, from: data)
            .filter { !$0.url.isEmpty }
            .map {
                var track = Track(name: $0.name, url: $0.url)
                track.startOffset = $0.startOffset
                track.endOffset = $0.endOffset
                return track
            }
    }
}
