import Foundation

/// Re-fetches artwork for favorites and recents, sharing one implementation
/// between the import flow and the Settings "Refresh thumbnails" action.
@MainActor
enum ThumbnailRefresher {
    /// Re-fetches the artwork for every non-custom favorite and recent track,
    /// reporting progress as `(completed, total)`.
    static func refreshAll(progress: @escaping (Int, Int) -> Void = { _, _ in }) async {
        var urls: [String] = []
        var seen = Set<String>()
        let sources =
            FavoritesStore.shared.items.map { ($0.url, $0.hasCustomThumbnail) }
            + RecentsStore.shared.items.map { ($0.url, $0.hasCustomThumbnail) }
        for (url, custom) in sources where !url.isEmpty && custom != true {
            if seen.insert(url).inserted { urls.append(url) }
        }
        await refresh(urls: urls, progress: progress)
    }

    /// Fetches and applies artwork for the given URLs. Favorites and recents are
    /// both updated; custom artwork is never overwritten by the stores.
    static func refresh(urls: [String], progress: @escaping (Int, Int) -> Void = { _, _ in }) async {
        guard !urls.isEmpty else {
            progress(0, 0)
            return
        }
        progress(0, urls.count)
        await withTaskGroup(of: (String, Data?).self) { group in
            for url in urls {
                group.addTask { (url, await StreamResolver.thumbnail(for: url)) }
            }
            var completed = 0
            for await (url, data) in group {
                if let data {
                    FavoritesStore.shared.setThumbnail(data, for: url)
                    RecentsStore.shared.setThumbnail(data, for: url)
                }
                completed += 1
                progress(completed, urls.count)
            }
        }
    }
}
