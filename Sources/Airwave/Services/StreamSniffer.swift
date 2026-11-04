import Foundation

/// Classifies a stream from its MIME type or leading bytes, independent of the
/// URL extension, so extensionless HLS/audio endpoints resolve correctly.
///
/// Foundation-only so the classification can be covered by the smoke test.
enum StreamSniffer {
    enum Kind: Equatable { case hls, audio, page }

    private static let hlsMimeTypes: Set<String> = [
        "application/vnd.apple.mpegurl",
        "application/x-mpegurl",
        "application/mpegurl",
        "audio/mpegurl",
        "audio/x-mpegurl",
    ]

    /// Lowercases and strips parameters (`; charset=…`) from a MIME type.
    static func normalize(_ mimeType: String?) -> String? {
        guard let mimeType else { return nil }
        return mimeType.lowercased().split(separator: ";").first.map(String.init)
    }

    /// Classifies from the response MIME type alone, or nil when inconclusive.
    static func kind(forMimeType mimeType: String?) -> Kind? {
        guard let mime = normalize(mimeType) else { return nil }
        if hlsMimeTypes.contains(mime) { return .hls }
        if mime.contains("html") { return .page }
        if mime.hasPrefix("audio/") || mime.hasPrefix("video/") || mime == "application/octet-stream" {
            return .audio
        }
        return nil
    }

    /// Classifies from the leading bytes when the MIME type is inconclusive.
    /// HLS playlists start with `#EXTM3U`; HTML pages are rejected.
    static func kind(forBody data: Data, mimeType: String?) -> Kind? {
        if let mimeKind = kind(forMimeType: mimeType) { return mimeKind }
        let text = String(decoding: data.prefix(2048), as: UTF8.self)
        if text.contains("#EXTM3U") { return .hls }
        let lowered = text.lowercased()
        if lowered.contains("<!doctype html") || lowered.contains("<html") { return .page }
        return nil
    }
}
