import Foundation
import AppKit
#if YOUTUBEKIT
import YouTubeKit
#endif

/// Turns a page URL into a playable audio stream URL (+ title, thumbnail, HTTP headers).
/// Direct audio / HLS links are used as-is. Backend chosen at build time (see make-app.sh).
enum StreamResolver {
    struct Resolved {
        let streamURL: URL
        let title: String?
        var thumbnailURL: URL? = nil
        var headers: [String: String] = [:]
    }

    enum ResolveError: LocalizedError {
        case invalidURL, ytdlpMissing, unsupported, failed(String)
        var errorDescription: String? {
            switch self {
            case .invalidURL: return "That doesn't look like a valid link."
            case .ytdlpMissing: return "yt-dlp was not found. Install it with `brew install yt-dlp` or set its path in Preferences."
            case .unsupported: return "This build (YouTubeKit) only plays YouTube and direct audio links."
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
        #if YOUTUBEKIT
        return try await resolveYouTubeKit(url)
        #else
        return try await runYtDlp(url: trimmed)
        #endif
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

    // MARK: yt-dlp backend

    static func ytdlpPath() -> String? {
        let custom = UserDefaults.standard.string(forKey: Prefs.ytdlpPath) ?? ""
        let bundled = Bundle.main.url(forResource: "yt-dlp", withExtension: nil)?.path ?? ""
        let candidates = [custom, bundled, "/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp", "/usr/bin/yt-dlp"]
        return candidates.first { !$0.isEmpty && FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func runYtDlp(url: String) async throws -> Resolved {
        guard let bin = ytdlpPath() else { throw ResolveError.ytdlpMissing }
        return try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: bin)
                // AVPlayer can't open WebM/Opus or DASH (the cause of "Cannot Open").
                // Prefer AAC/M4A, then HLS (live streams), then anything single-file.
                let format = "bestaudio[ext=m4a]/bestaudio[acodec^=mp4a]/91/92/93/best[protocol^=m3u8]/bestaudio[protocol^=http][ext!=webm]/best[ext=mp4]/best"
                p.arguments = ["-f", format, "--no-playlist", "--no-warnings",
                               "-O", "%(title)s", "-O", "%(thumbnail)s",
                               "-O", "%(http_headers)j", "-O", "%(url)s", url]
                let out = Pipe(), err = Pipe()
                p.standardOutput = out; p.standardError = err
                do { try p.run() } catch {
                    cont.resume(throwing: ResolveError.failed(error.localizedDescription)); return
                }
                let outData = out.fileHandleForReading.readDataToEndOfFile()
                let errData = err.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                let lines = String(decoding: outData, as: UTF8.self)
                    .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
                guard p.terminationStatus == 0, lines.count >= 4,
                      let stream = URL(string: lines[3].trimmingCharacters(in: .whitespaces)),
                      stream.scheme != nil else {
                    let msg = String(decoding: errData, as: UTF8.self)
                        .split(separator: "\n").last.map(String.init) ?? "Unknown error"
                    cont.resume(throwing: ResolveError.failed(msg)); return
                }
                var headers: [String: String] = [:]
                if let d = lines[2].data(using: .utf8),
                   let h = try? JSONSerialization.jsonObject(with: d) as? [String: String] { headers = h }
                let thumb = lines[1] == "NA" ? nil : URL(string: lines[1])
                cont.resume(returning: Resolved(streamURL: stream, title: lines[0] == "NA" ? nil : lines[0],
                                                thumbnailURL: thumb, headers: headers))
            }
        }
    }

    // MARK: YouTubeKit backend

    #if YOUTUBEKIT
    private static func resolveYouTubeKit(_ url: URL) async throws -> Resolved {
        let host = url.host?.lowercased() ?? ""
        guard host.contains("youtube.com") || host.contains("youtu.be") else { throw ResolveError.unsupported }
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
    #endif
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
