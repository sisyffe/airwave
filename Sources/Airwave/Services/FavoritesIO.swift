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

    enum ConflictStrategy {
        case createDuplicates
        case overwrite
        case ignore
    }

    /// Imported favorites that share a name with existing ones. Computed before
    /// anything is written, so the user can choose how to resolve it.
    struct ImportPlan {
        /// Incoming favorites in file order, with each conflict paired to the
        /// existing favorite that has its name.
        var entries: [Entry]

        enum Entry {
            case added(Favorite)
            case conflict(existing: Favorite, incoming: Favorite)
        }

        var conflicts: [(existing: Favorite, incoming: Favorite)] {
            entries.compactMap { entry in
                if case .conflict(let existing, let incoming) = entry { return (existing, incoming) }
                return nil
            }
        }
    }

    static func plan(_ incoming: [Favorite], against existing: [Favorite]) -> ImportPlan {
        ImportPlan(
            entries: incoming.map { favorite in
                if let match = existing.first(where: { Favorite.nameKey($0.name) == Favorite.nameKey(favorite.name) }) {
                    return .conflict(existing: match, incoming: favorite)
                }
                return .added(favorite)
            })
    }

    /// Returns the merged list after applying `strategy` to every conflict,
    /// keeping file order. Overwrite and Ignore never touch non-conflicting favorites.
    static func apply(_ plan: ImportPlan, to existing: [Favorite], strategy: ConflictStrategy) -> [Favorite] {
        var merged = existing
        for entry in plan.entries {
            switch entry {
            case .added(let favorite):
                merged.append(favorite)
            case .conflict(let existingFavorite, let incoming):
                switch strategy {
                case .ignore:
                    continue
                case .createDuplicates:
                    var renamed = incoming
                    renamed.name = uniqueName(for: incoming.name, among: merged)
                    merged.append(renamed)
                case .overwrite:
                    guard let index = merged.firstIndex(where: { $0.id == existingFavorite.id }) else { continue }
                    // A true overwrite: the imported favorite gets a new identity, so it
                    // replaces the old one everywhere (player, recents) without inheriting its trim or artwork.
                    merged[index] = Favorite(
                        name: incoming.name, url: incoming.url, startOffset: incoming.startOffset, endOffset: incoming.endOffset)
                }
            }
        }
        return merged
    }

    /// "Name", then "Name (2)", "Name (3)", … whichever is first free.
    static func uniqueName(for name: String, among favorites: [Favorite]) -> String {
        var suffix = 2
        var candidate = "\(name) (\(suffix))"
        while !Favorite.isNameAvailable(candidate, among: favorites) {
            suffix += 1
            candidate = "\(name) (\(suffix))"
        }
        return candidate
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
