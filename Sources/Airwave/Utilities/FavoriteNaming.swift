import Foundation

/// Favorite names are unique (links may repeat), so a taken name is
/// disambiguated with a numeric suffix rather than rejected.
enum FavoriteNaming {
    /// Returns `name` (or `url` when blank) disambiguated so it does not collide
    /// with `taken`.
    static func unique(_ name: String, url: String, taken: Set<String>) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? url : trimmed
        guard taken.contains(base) else { return base }
        var index = 2
        while taken.contains("\(base) \(index)") { index += 1 }
        return "\(base) \(index)"
    }
}
