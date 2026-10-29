import Foundation

/// Reads ICY (Shoutcast/Icecast) inline metadata from a direct audio stream.
///
/// This opens a separate, audio-less connection to the stream and parses the
/// `icy-metaint` metadata blocks to surface the station name and the current
/// song. `AVPlayer` does not expose this information.
enum ICYMetadata {
    struct Info: Equatable {
        var station: String?
        var song: String?
    }

    private static let eligibleExtensions: Set<String> = ["mp3", "aac", "m4a", "ogg", "opus"]

    /// Whether the URL points at a stream type that can carry ICY metadata.
    static func isEligible(_ url: URL) -> Bool {
        eligibleExtensions.contains(url.pathExtension.lowercased())
    }

    /// Emits an `Info` whenever the station name or current song changes, until
    /// the stream ends, errors, or the consuming task is cancelled.
    static func stream(from url: URL) -> AsyncStream<Info> {
        AsyncStream { continuation in
            let task = Task { await run(url: url, continuation: continuation) }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func run(url: URL, continuation: AsyncStream<Info>.Continuation) async {
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        req.setValue("1", forHTTPHeaderField: "Icy-MetaData")
        req.setValue("Airwave/1.1", forHTTPHeaderField: "User-Agent")
        req.setValue("*/*", forHTTPHeaderField: "Accept")

        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: req)
            guard let http = response as? HTTPURLResponse else { return }

            let station = http.value(forHTTPHeaderField: "icy-name").flatMap { $0.isEmpty ? nil : $0 }
            guard let metaIntStr = http.value(forHTTPHeaderField: "icy-metaint"),
                  let metaInt = Int(metaIntStr), metaInt > 0 else {
                if let station { continuation.yield(Info(station: station, song: nil)) }
                return
            }
            if let station { continuation.yield(Info(station: station, song: nil)) }

            var iterator = bytes.makeAsyncIterator()
            while !Task.isCancelled {
                // Skip `metaInt` bytes of audio.
                var skipped = 0
                while skipped < metaInt {
                    guard try await iterator.next() != nil else { return }
                    skipped += 1
                }
                // Length byte, in 16-byte units (0 = no metadata this block).
                guard let lengthByte = try await iterator.next() else { return }
                let metaLength = Int(lengthByte) * 16
                guard metaLength > 0 else { continue }

                var meta = [UInt8]()
                meta.reserveCapacity(metaLength)
                var read = 0
                while read < metaLength {
                    guard let byte = try await iterator.next() else { return }
                    meta.append(byte)
                    read += 1
                }
                if let song = parseStreamTitle(meta) {
                    continuation.yield(Info(station: station, song: song))
                }
            }
        } catch {
            return
        }
    }

    private static func parseStreamTitle(_ bytes: [UInt8]) -> String? {
        let text = String(decoding: bytes, as: UTF8.self)
        guard let start = text.range(of: "StreamTitle='") else { return nil }
        let after = text[start.upperBound...]
        guard let end = after.firstIndex(of: "'") else { return nil }
        let title = String(after[after.startIndex..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }
}
