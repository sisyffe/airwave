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

    /// How to resolve incoming favorites whose name collides with an existing one.
    enum ImportPolicy { case suffix, overwrite, skip }

    /// The result of comparing an imported file against the current list, before
    /// anything is mutated.
    struct ImportPlan {
        /// Incoming favorites that add a new identity.
        let additions: [Favorite]
        /// Incoming favorites whose name collides with an existing one.
        let conflicts: [Favorite]
        /// How many incoming favorites were exact duplicates and auto-merged.
        let duplicates: Int
        var hasConflicts: Bool { !conflicts.isEmpty }
    }

    /// Classifies imported favorites against the existing list without mutating
    /// anything. Exact (name, link, trim) matches are auto-merged; a name
    /// collision on a different track becomes a conflict.
    static func plan(_ incoming: [Favorite], into existing: [Favorite]) -> ImportPlan {
        var identities = Set(existing.map(\.identityKey))
        var names = Set(existing.map(\.name))
        var additions: [Favorite] = []
        var conflicts: [Favorite] = []
        var duplicates = 0
        for favorite in incoming where !favorite.url.isEmpty {
            if identities.contains(favorite.identityKey) {
                duplicates += 1
                continue
            }
            identities.insert(favorite.identityKey)
            if names.contains(favorite.name) {
                conflicts.append(favorite)
            } else {
                names.insert(favorite.name)
                additions.append(favorite)
            }
        }
        return ImportPlan(additions: additions, conflicts: conflicts, duplicates: duplicates)
    }

    /// Applies a plan with the chosen conflict policy. Returns the merged list
    /// and how many favorites were added or replaced.
    static func apply(
        _ plan: ImportPlan, policy: ImportPolicy, to existing: [Favorite]
    ) -> (items: [Favorite], added: Int) {
        var result = existing
        var names = Set(result.map(\.name))
        var identities = Set(result.map(\.identityKey))
        var added = 0

        func insert(_ favorite: Favorite) {
            guard identities.insert(favorite.identityKey).inserted else { return }
            var item = favorite
            item.name = FavoriteNaming.unique(item.name, url: item.url, taken: names)
            names.insert(item.name)
            identities.insert(item.identityKey)
            result.append(item)
            added += 1
        }

        for item in plan.additions { insert(item) }
        switch policy {
        case .skip:
            break
        case .suffix:
            for item in plan.conflicts { insert(item) }
        case .overwrite:
            for item in plan.conflicts {
                if let index = result.firstIndex(where: { $0.name == item.name }) {
                    identities.remove(result[index].identityKey)
                    result[index] = item
                    identities.insert(item.identityKey)
                    added += 1
                } else {
                    insert(item)
                }
            }
        }
        return (result, added)
    }

    /// Merges imported favorites into the existing list, suffixing name
    /// collisions and skipping exact duplicates.
    static func merge(_ incoming: [Favorite], into existing: [Favorite]) -> (items: [Favorite], added: Int) {
        apply(plan(incoming, into: existing), policy: .suffix, to: existing)
    }

    struct ExportedFavorite: Codable {
        let name: String
        let url: String
        /// Optional trim offsets; omitted from the JSON when unset.
        let startOffset: TimeInterval?
        let endOffset: TimeInterval?
    }
}
