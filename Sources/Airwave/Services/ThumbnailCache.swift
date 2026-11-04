import AppKit
import CryptoKit

/// Content-addressed store for thumbnail images, shared by the favorites and
/// recents stores.
///
/// Each item owns a `thumbnailKey` (the SHA-256 of its canonical bytes) while
/// the bytes themselves live once on disk under `Thumbnails/<key>.png`. Two
/// owners with identical artwork therefore share a single file, and two owners
/// with different artwork stay independent even when they point at the same
/// URL. Images are never persisted in UserDefaults.
@MainActor
enum ThumbnailCache {
    /// Longest side of a stored thumbnail, in pixels. The largest on-screen
    /// thumbnail is the 120 pt Now Playing card, i.e. 240 px at @2x, so 256 px
    /// stays sharp with a little headroom without being wasteful.
    nonisolated static let maxSide: CGFloat = 256

    private struct Entry {
        let source: Data
        let thumbnail: Data
    }

    /// Memo of canonical thumbnails by source URL, so the same fetched cover is
    /// not re-downscaled on every play.
    private static var entries: [String: Entry] = [:]

    nonisolated private static var directory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Airwave/Thumbnails", isDirectory: true)
    }

    nonisolated static func hash(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

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

    /// Canonicalizes `data`, writes it as a content-addressed resource (only when
    /// absent) and returns the resource key together with the canonical bytes.
    /// Returns nil when `data` is not a decodable image.
    @discardableResult
    static func store(_ data: Data, for url: String) -> (key: String, data: Data)? {
        guard let canonical = canonical(data, for: url) else { return nil }
        let key = hash(of: canonical)
        let fileURL = directory.appendingPathComponent("\(key).png")
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? canonical.write(to: fileURL, options: .atomic)
        }
        return (key, canonical)
    }

    /// Loads the canonical bytes for a stored resource key, if present.
    static func data(forKey key: String?) -> Data? {
        guard let key, !key.isEmpty else { return nil }
        return try? Data(contentsOf: directory.appendingPathComponent("\(key).png"))
    }

    /// Removes every resource not referenced by `keys`. Called after the stores
    /// load so deleted favorites/recents do not leave orphaned files behind.
    static func prune(keeping keys: Set<String>) {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else { return }
        for file in files where file.pathExtension == "png" && !keys.contains(file.deletingPathExtension().lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// Deletes the whole cache directory (used by the refresh action).
    static func removeAll() {
        try? FileManager.default.removeItem(at: directory)
        entries.removeAll()
    }

    /// Hydrates each item's in-memory thumbnail from its resource key, migrating
    /// any legacy embedded bytes to disk on the way. Items whose key no longer
    /// resolves are cleared so they fall back to the placeholder.
    static func persisted<Item>(
        _ items: [Item],
        url: KeyPath<Item, String>,
        thumbnail: WritableKeyPath<Item, Data?>,
        thumbnailKey: WritableKeyPath<Item, String?>
    ) -> [Item] {
        items.map { item in
            var item = item
            if let legacy = item[keyPath: thumbnail], let stored = store(legacy, for: item[keyPath: url]) {
                item[keyPath: thumbnail] = stored.data
                item[keyPath: thumbnailKey] = stored.key
            } else if let data = data(forKey: item[keyPath: thumbnailKey]) {
                item[keyPath: thumbnail] = data
            } else {
                item[keyPath: thumbnail] = nil
                item[keyPath: thumbnailKey] = nil
            }
            return item
        }
    }

    /// Returns copies with in-memory thumbnails removed, for JSON persistence
    /// that carries only the lightweight `thumbnailKey`.
    static func stripping<Item>(_ items: [Item], thumbnail: WritableKeyPath<Item, Data?>) -> [Item] {
        items.map { item in
            var item = item
            item[keyPath: thumbnail] = nil
            return item
        }
    }
}
