import AppKit
import CryptoKit

/// Content-addressed thumbnail files in Application Support, shared by the
/// whole app. Tracks hold only the key (the SHA-256 of the stored PNG), so an
/// identical image is stored once.
enum ThumbnailStore {
    /// Longest side of a stored thumbnail, in points.
    nonisolated static let maxSide: CGFloat = 256

    private static let memory = NSCache<NSString, NSData>()

    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Airwave/Thumbnails", isDirectory: true)
    }

    /// Downscales and stores an image, returning its key; nil if not an image.
    static func save(_ data: Data) -> String? {
        guard let image = NSImage(data: data), let png = image.downsized(maxSide: maxSide) else { return nil }
        let key = SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()
        let file = directory.appendingPathComponent(key + ".png")
        if !FileManager.default.fileExists(atPath: file.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? png.write(to: file, options: .atomic)
        }
        memory.setObject(png as NSData, forKey: key as NSString)
        return key
    }

    static func data(for key: String?) -> Data? {
        guard let key else { return nil }
        if let cached = memory.object(forKey: key as NSString) { return cached as Data }
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(key + ".png")) else { return nil }
        memory.setObject(data as NSData, forKey: key as NSString)
        return data
    }

    /// Deletes files no track refers to. Files modified after `cutoff` are
    /// spared so an image saved while pruning runs is never lost. Meant to run
    /// off the main thread.
    nonisolated static func prune(keeping keys: Set<String>, modifiedBefore cutoff: Date) {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Airwave/Thumbnails", isDirectory: true)
        let files =
            (try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for file in files where !keys.contains(file.deletingPathExtension().lastPathComponent) {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, modified < cutoff { try? FileManager.default.removeItem(at: file) }
        }
    }
}
