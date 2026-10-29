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
    }

    enum ResolveError: LocalizedError {
        case invalidURL, unsupported, failed(String)
        var errorDescription: String? {
            switch self {
            case .invalidURL: return "That doesn't look like a valid link."
            case .unsupported: return "Airwave uses YouTubeKit: paste a YouTube URL or a direct audio/HLS stream link. Other website pages are not supported."
            case .failed(let msg): return "Couldn't get audio from this link.\n\(msg)"
            }
        }
    }

    private static let directExtensions: Set<String> = ["mp3", "aac", "m4a", "m3u8", "ogg", "opus", "wav", "flac", "pls"]

    static func resolve(_ input: String) async throws -> Resolved {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme, ["http", "https"].contains(scheme) else {
            throw ResolveError.invalidURL
        }
        if directExtensions.contains(url.pathExtension.lowercased()) {
            return Resolved(streamURL: url, title: nil)
        }
        return try await resolveYouTubeKit(url)
    }

    // MARK: Thumbnails

    /// Downloads and downsizes a thumbnail. Falls back to the page's og:image, then its favicon.
    static func fetchThumbnail(_ resolved: URL?, page: String) async -> Data? {
        var candidates: [URL] = []
        if let resolved { candidates.append(resolved) }
        if let pageURL = URL(string: page) {
            if let og = await ogImage(pageURL) { candidates.append(og) }
            if let host = pageURL.host {
                candidates.append(URL(string: "https://www.google.com/s2/favicons?sz=128&domain=\(host)")!)
            }
        }
        for c in candidates {
            if let (data, _) = try? await URLSession.shared.data(from: c),
               let img = NSImage(data: data), let small = img.downsized(maxSide: 256) {
                return small
            }
        }
        return nil
    }

    private static func ogImage(_ page: URL) async -> URL? {
        var req = URLRequest(url: page, timeoutInterval: 8)
        req.setValue("Mozilla/5.0 (Macintosh)", forHTTPHeaderField: "User-Agent")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp.mimeType ?? "").contains("html") else { return nil }
        let html = String(decoding: data.prefix(300_000), as: UTF8.self)
        let pattern = #"<meta[^>]+(?:property|name)=["'](?:og:image|twitter:image)["'][^>]+content=["']([^"']+)["']"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let m = re.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let r = Range(m.range(at: 1), in: html) else { return nil }
        return URL(string: String(html[r]).replacingOccurrences(of: "&amp;", with: "&"), relativeTo: page)?.absoluteURL
    }

    // MARK: YouTubeKit

    private static func resolveYouTubeKit(_ url: URL) async throws -> Resolved {
        let host = url.host?.lowercased() ?? ""
        guard host == "youtube.com" || host.hasSuffix(".youtube.com") || host == "youtu.be" else { throw ResolveError.unsupported }
        do {
            let yt = YouTube(url: url)
            let meta = try? await yt.metadata
            let title = meta?.title
            let thumb = meta?.thumbnail?.url
            // Live streams: HLS manifest
            if let live = try? await yt.livestreams.filter({ $0.streamType == .hls }).first {
                return Resolved(streamURL: live.url, title: title, thumbnailURL: thumb)
            }
            let streams = try await yt.streams
            let audio = streams.filterAudioOnly().filter { $0.fileExtension == .m4a }.highestAudioBitrateStream()
                ?? streams.filterVideoAndAudio().filter { $0.isNativelyPlayable }.lowestResolutionStream()
            guard let s = audio else { throw ResolveError.failed("No playable audio stream found.") }
            return Resolved(streamURL: s.url, title: title, thumbnailURL: thumb)
        } catch let e as ResolveError {
            throw e
        } catch {
            throw ResolveError.failed(error.localizedDescription)
        }
    }
}

extension NSImage {
    /// Returns JPEG data scaled so the longest side is at most `maxSide` px.
    func downsized(maxSide: CGFloat) -> Data? {
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(1, maxSide / max(size.width, size.height))
        let target = NSSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(target.width), pixelsHigh: Int(target.height),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        draw(in: NSRect(origin: .zero, size: target))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}
