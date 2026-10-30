import Foundation
import AppKit
import YouTubeKit

/// Turns a page URL into a playable audio stream URL (+ title, thumbnail, HTTP headers).
/// Direct audio / HLS links are used as-is. YouTube pages are resolved with the bundled YouTubeKit library.
enum StreamResolver {
    struct Resolved {
        let streamURL: URL
        let title: String?
        var thumbnailURL: URL? = nil
        var headers: [String: String] = [:]
        /// True for direct audio/HLS links (as opposed to resolved YouTube pages).
        var isDirect: Bool = false
    }

    enum ResolveError: LocalizedError {
        case invalidURL, unsupported, failed(String)
        var errorDescription: String? {
            switch self {
            case .invalidURL: return "That doesn't look like a valid link."
            case .unsupported: return "Airwave uses YouTubeKit: paste a YouTube URL or a direct audio/HLS stream link. Other website pages are not supported."
            case .failed(let message): return "Couldn't get audio from this link.\n\(message)"
            }
        }
    }

    /// URL extensions that are handed straight to AVPlayer.
    private static let directExtensions: Set<String> = ["mp3", "aac", "m4a", "m3u8", "ogg", "opus", "wav", "flac"]

    private static let browserUserAgent = "Mozilla/5.0 (Macintosh)"
    private static let pageRequestTimeout: TimeInterval = 8
    /// Upper bound on how much page HTML to scan for metadata tags.
    private static let maxHTMLBytes = 300_000
    private static let faviconServiceBaseURL = "https://www.google.com/s2/favicons?sz=128&domain="
    private static let openGraphImagePattern =
        #"<meta[^>]+(?:property|name)=["'](?:og:image|twitter:image)["'][^>]+content=["']([^"']+)["']"#

    static func resolve(_ input: String) async throws -> Resolved {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme, ["http", "https"].contains(scheme) else {
            throw ResolveError.invalidURL
        }
        if directExtensions.contains(url.pathExtension.lowercased()) {
            return Resolved(streamURL: url, title: nil, isDirect: true)
        }
        return try await resolveYouTube(url)
    }

    // MARK: Thumbnails

    /// Downloads and downsizes a thumbnail. Falls back to the page's og:image, then its favicon.
    static func fetchThumbnail(_ thumbnailURL: URL?, page: String) async -> Data? {
        var candidates: [URL] = []
        if let thumbnailURL { candidates.append(thumbnailURL) }
        if let pageURL = URL(string: page) {
            if let ogImageURL = await openGraphImage(for: pageURL) { candidates.append(ogImageURL) }
            if let host = pageURL.host {
                candidates.append(URL(string: faviconServiceBaseURL + host)!)
            }
        }
        for candidate in candidates {
            if let (data, _) = try? await URLSession.shared.data(from: candidate),
               let image = NSImage(data: data), let downscaled = image.downsized(maxSide: ThumbnailCache.maxSide) {
                return downscaled
            }
        }
        return nil
    }

    private static func openGraphImage(for page: URL) async -> URL? {
        var request = URLRequest(url: page, timeoutInterval: pageRequestTimeout)
        request.setValue(browserUserAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response.mimeType ?? "").contains("html") else { return nil }
        let html = String(decoding: data.prefix(maxHTMLBytes), as: UTF8.self)
        guard let regex = try? NSRegularExpression(pattern: openGraphImagePattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let matchRange = Range(match.range(at: 1), in: html) else { return nil }
        let imageURL = String(html[matchRange]).replacingOccurrences(of: "&amp;", with: "&")
        return URL(string: imageURL, relativeTo: page)?.absoluteURL
    }

    // MARK: YouTubeKit

    private static func resolveYouTube(_ url: URL) async throws -> Resolved {
        let host = url.host?.lowercased() ?? ""
        guard host == "youtube.com" || host.hasSuffix(".youtube.com") || host == "youtu.be" else { throw ResolveError.unsupported }
        do {
            let youtube = YouTube(url: url)
            let metadata = try? await youtube.metadata
            let title = metadata?.title
            let thumbnailURL = metadata?.thumbnail?.url
            // Live streams: HLS manifest
            if let live = try? await youtube.livestreams.filter({ $0.streamType == .hls }).first {
                return Resolved(streamURL: live.url, title: title, thumbnailURL: thumbnailURL)
            }
            let streams = try await youtube.streams
            let audio = streams.filterAudioOnly().filter { $0.fileExtension == .m4a }.highestAudioBitrateStream()
                ?? streams.filterVideoAndAudio().filter { $0.isNativelyPlayable }.lowestResolutionStream()
            guard let stream = audio else { throw ResolveError.failed("No playable audio stream found.") }
            return Resolved(streamURL: stream.url, title: title, thumbnailURL: thumbnailURL)
        } catch let error as ResolveError {
            throw error
        } catch {
            throw ResolveError.failed(error.localizedDescription)
        }
    }
}
