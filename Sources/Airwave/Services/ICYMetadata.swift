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
    private static let requestTimeout: TimeInterval = 15
    /// Each metadata length byte counts this many bytes of metadata.
    private static let metadataBlockUnitSize = 16

    /// Whether the URL points at a stream type that can carry ICY metadata.
    static func isEligible(_ url: URL) -> Bool {
        eligibleExtensions.contains(url.pathExtension.lowercased())
    }

    /// Emits an `Info` whenever the station name or current song changes, until
    /// the stream ends, errors, or the consuming task is cancelled.
    static func stream(from url: URL) -> AsyncStream<Info> {
        AsyncStream { continuation in
            let task = Task { await read(url: url, continuation: continuation) }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func read(url: URL, continuation: AsyncStream<Info>.Continuation) async {
        var request = URLRequest(url: url)
        request.timeoutInterval = requestTimeout
        request.setValue("1", forHTTPHeaderField: "Icy-MetaData")
        request.setValue(AppInfo.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")

        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return }

            let station = httpResponse.value(forHTTPHeaderField: "icy-name").flatMap { $0.isEmpty ? nil : $0 }
            guard let metadataIntervalValue = httpResponse.value(forHTTPHeaderField: "icy-metaint"),
                let metadataInterval = Int(metadataIntervalValue), metadataInterval > 0
            else {
                if let station { continuation.yield(Info(station: station, song: nil)) }
                return
            }
            if let station { continuation.yield(Info(station: station, song: nil)) }

            var iterator = bytes.makeAsyncIterator()
            while !Task.isCancelled {
                // Skip `metadataInterval` bytes of audio.
                var bytesSkipped = 0
                while bytesSkipped < metadataInterval {
                    guard !Task.isCancelled, try await iterator.next() != nil else { return }
                    bytesSkipped += 1
                }
                // Length byte, in 16-byte units (0 = no metadata this block).
                guard let lengthByte = try await iterator.next() else { return }
                let metadataLength = Int(lengthByte) * metadataBlockUnitSize
                guard metadataLength > 0 else { continue }

                var metadataBytes = [UInt8]()
                metadataBytes.reserveCapacity(metadataLength)
                var bytesRead = 0
                while bytesRead < metadataLength {
                    guard !Task.isCancelled, let byte = try await iterator.next() else { return }
                    metadataBytes.append(byte)
                    bytesRead += 1
                }
                if let song = parseStreamTitle(metadataBytes) {
                    continuation.yield(Info(station: station, song: song))
                }
            }
        } catch {
            return
        }
    }

    /// Extracts the value of `StreamTitle='…'` from one ICY metadata block.
    /// Internal (not private) so it can be covered by the smoke test.
    static func parseStreamTitle(_ bytes: [UInt8]) -> String? {
        let text = String(decoding: bytes, as: UTF8.self)
        guard let start = text.range(of: "StreamTitle='") else { return nil }
        let after = text[start.upperBound...]
        guard let end = after.firstIndex(of: "'") else { return nil }
        let title = String(after[after.startIndex..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }
}
