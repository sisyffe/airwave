import Foundation

/// Classifies a response as a playable audio or HLS stream from its headers and
/// first bytes. Used for links without a recognised file extension.
enum StreamProbe {
    /// Only the start of the body is needed: an HLS playlist begins with
    /// `#EXTM3U`, and live streams never finish, so the body is never read to the end.
    static let sampleByteCount = 1024

    private static let hlsSignature = Array("#EXTM3U".utf8)

    /// Whether the response can be handed to AVPlayer.
    static func isPlayable(contentType: String?, sample: [UInt8]) -> Bool {
        if sample.starts(with: hlsSignature) { return true }
        guard let mimeType = contentType?.split(separator: ";").first.map({ $0.trimmingCharacters(in: .whitespaces).lowercased() })
        else { return false }
        return mimeType.hasPrefix("audio/") || mimeType == "application/vnd.apple.mpegurl"
            || mimeType == "application/x-mpegurl"
    }
}
