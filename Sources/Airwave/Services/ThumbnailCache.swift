import AppKit
import CryptoKit

/// Content-addressed store for thumbnail images.
///
/// Images are downscaled once, written to the caches directory under the SHA-256
/// of their bytes, and referred to elsewhere by that key. Favorites, recents and
/// the player only hold keys, so one image shared by several tracks is stored
/// once, and the persisted JSON stays small.
@MainActor
enum ThumbnailCache {
    /// Longest side of a stored thumbnail, in points. 360 px is 3x the 120 pt
    /// Now Playing artwork, so it stays sharp on Retina displays.
    nonisolated static let maxSide: CGFloat = 360

    /// Keeps decoded images for the lists so scrolling does not re-read files.
    private static let images = NSCache<NSString, NSImage>()

    private static let directory: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let bundleID = Bundle.main.bundleIdentifier ?? "Airwave"
        return base.appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("Thumbnails", isDirectory: true)
    }()

    /// Downscales `data` and stores it, returning its key. Nil when `data` is not an image.
    static func store(_ data: Data) -> String? {
        let key = key(for: data)
        let file = url(for: key)
        if FileManager.default.fileExists(atPath: file.path) { return key }
        guard let image = NSImage(data: data), let png = image.downsized(maxSide: maxSide) else { return nil }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try png.write(to: file, options: .atomic)
        } catch {
            return nil
        }
        return key
    }

    /// Stored bytes for `key`, or nil when the file is missing (for example after the system purged the cache).
    static func data(for key: String?) -> Data? {
        guard let key else { return nil }
        return try? Data(contentsOf: url(for: key))
    }

    /// Decoded image for `key`, cached in memory.
    static func image(for key: String?) -> NSImage? {
        guard let key else { return nil }
        if let cached = images.object(forKey: key as NSString) { return cached }
        guard let data = data(for: key), let image = NSImage(data: data) else { return nil }
        images.setObject(image, forKey: key as NSString)
        return image
    }

    /// Removes every file whose key is not in `keeping`. Run after loading so
    /// thumbnails no longer referenced by any favorite or recent are reclaimed.
    static func prune(keeping keys: Set<String>) {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else { return }
        for file in files where !keys.contains(file.deletingPathExtension().lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private static func key(for data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func url(for key: String) -> URL {
        directory.appendingPathComponent(key).appendingPathExtension("png")
    }
}
