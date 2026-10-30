import Foundation
import AVFoundation
import MediaPlayer
import AppKit

/// AVPlayer wrapper that publishes state and integrates with macOS Now Playing
/// (Control Center, media keys, AirPods, Touch Bar, lock screen).
@MainActor
final class AudioPlayer: ObservableObject {
    static let shared = AudioPlayer()

    enum State: Equatable { case idle, loading, playing, paused }

    @Published private(set) var state: State = .idle
    @Published private(set) var title: String = ""
    @Published private(set) var sourceURL: String = ""
    /// Thumbnail of the current link (PNG/JPEG data), if one could be fetched.
    @Published private(set) var artwork: Data?
    /// Current song reported by ICY metadata for direct radio streams (nil = none).
    @Published private(set) var streamTitle: String?
    /// Last playback error, shown as an alert by the UI (nil = none).
    @Published private(set) var lastError: String?
    @Published var volume: Float {
        didSet { player.volume = volume; UserDefaults.standard.set(volume, forKey: Prefs.volume) }
    }

    private(set) var hasStarted = false
    private let player = AVPlayer()
    private var statusObservation: NSKeyValueObservation?
    private var rateObservation: NSKeyValueObservation?
    /// ICY metadata reader task for the current direct stream, if any.
    private var icyTask: Task<Void, Never>?
    /// Incremented by every play() call; stale async work bails out if it changed.
    private var generation = 0

    var isPlaying: Bool { state == .playing }

    private init() {
        let saved = UserDefaults.standard.object(forKey: Prefs.volume) as? Float
        volume = saved ?? Prefs.defaultVolume
        player.volume = volume
        player.automaticallyWaitsToMinimizeStalling = true
        setupRemoteCommands()
        rateObservation = player.observe(\.timeControlStatus) { [weak self] player, _ in
            Task { @MainActor in self?.syncState(player.timeControlStatus) }
        }
    }

    // MARK: Playback

    /// What was playing before a new link was submitted, so it can be restored
    /// when the new link fails to load.
    private struct Snapshot {
        let url: String
        let title: String
        let artwork: Data?
        let item: AVPlayerItem?
        let wasPlaying: Bool
    }

    func play(urlString: String, title: String? = nil, artwork knownArtwork: Data? = nil) async {
        hasStarted = true
        lastError = nil
        generation += 1
        let playGeneration = generation
        let previous = Snapshot(url: sourceURL, title: self.title, artwork: artwork,
                                item: player.currentItem, wasPlaying: isPlaying)
        state = .loading
        streamTitle = nil
        icyTask?.cancel()
        icyTask = nil
        sourceURL = urlString
        self.title = title ?? urlString
        artwork = knownArtwork
        updateNowPlaying()
        do {
            let resolved = try await StreamResolver.resolve(urlString)
            guard playGeneration == generation else { return } // user switched meanwhile
            if title == nil, let resolvedTitle = resolved.title { self.title = resolvedTitle }
            // Apply stream-specific headers when supplied by the resolver.
            var options: [String: Any] = [:]
            if !resolved.headers.isEmpty { options["AVURLAssetHTTPHeaderFieldsKey"] = resolved.headers }
            let asset = AVURLAsset(url: resolved.streamURL, options: options)
            let item = AVPlayerItem(asset: asset)
            statusObservation = item.observe(\.status) { [weak self] item, _ in
                Task { @MainActor in
                    guard let self, item.status == .failed, self.generation == playGeneration else { return }
                    self.itemFailed(item, previous: previous)
                }
            }
            player.replaceCurrentItem(with: item)
            player.play()
            UserDefaults.standard.set(urlString, forKey: Prefs.lastURL)
            RecentsStore.shared.record(name: self.title, url: urlString, thumbnail: artwork)
            updateNowPlaying()
            startICYIfEligible(resolved, playGeneration: playGeneration)
            // Always refresh the artwork, even when a cached one was supplied
            // (from favorites/recents), so covers stay up to date on every play.
            let fetched = await StreamResolver.fetchThumbnail(resolved.thumbnailURL, page: urlString)
            if playGeneration == generation, let fetched, fetched != artwork {
                artwork = fetched
                updateNowPlaying()
                NotificationCenter.default.post(name: .airwaveArtwork, object: urlString, userInfo: ["data": fetched])
            }
        } catch {
            guard playGeneration == generation else { return } // a newer link owns the UI
            restore(previous) // keep whatever was playing…
            lastError = error.localizedDescription // …and surface the problem as an alert
        }
    }

    /// The item we just swapped in never actually started; put back what was playing before.
    private func itemFailed(_ item: AVPlayerItem, previous: Snapshot) {
        let message = item.error?.localizedDescription ?? "Playback failed"
        if case .loading = state { restore(previous) }
        lastError = message
    }

    private func restore(_ snapshot: Snapshot) {
        if let item = snapshot.item, player.currentItem !== item {
            player.replaceCurrentItem(with: item)
            if item.duration.isIndefinite {
                item.seek(to: .positiveInfinity, completionHandler: nil) // back to the live edge
            }
        }
        if snapshot.wasPlaying, snapshot.item != nil { player.play() }
        sourceURL = snapshot.url
        title = snapshot.title
        artwork = snapshot.artwork
        state = snapshot.item == nil ? .idle : (snapshot.wasPlaying ? .playing : .paused)
        updateNowPlaying()
    }

    func resume() {
        guard player.currentItem != nil else {
            if !sourceURL.isEmpty { Task { await play(urlString: sourceURL, title: title, artwork: artwork) } }
            return
        }
        // For live streams, jump back to the live edge after a pause.
        if let item = player.currentItem, item.duration.isIndefinite {
            item.seek(to: .positiveInfinity, completionHandler: nil)
        }
        player.play()
    }

    func pause() { player.pause() }
    func toggle() { isPlaying ? pause() : resume() }

    /// Re-resolve and reload the current source (fresh stream URL), keeping the
    /// existing title and artwork so the UI does not flicker.
    func refresh() {
        guard !sourceURL.isEmpty else { return }
        Task { await play(urlString: sourceURL, title: title, artwork: artwork) }
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        icyTask?.cancel()
        icyTask = nil
        streamTitle = nil
        sourceURL = ""
        title = ""
        artwork = nil
        state = .idle
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }

    /// Starts reading ICY metadata for direct radio streams. Adopts the station
    /// name as the title when the title is still just the raw URL.
    private func startICYIfEligible(_ resolved: StreamResolver.Resolved, playGeneration: Int) {
        guard resolved.isDirect, ICYMetadata.isEligible(resolved.streamURL) else { return }
        let url = resolved.streamURL
        icyTask = Task { [weak self] in
            for await info in ICYMetadata.stream(from: url) {
                guard let self, playGeneration == self.generation else { return }
                if let station = info.station, self.title == self.sourceURL {
                    self.title = station
                    RecentsStore.shared.record(name: station, url: self.sourceURL, thumbnail: self.artwork)
                }
                self.streamTitle = info.song
                self.updateNowPlaying()
            }
        }
    }

    func clearError() { lastError = nil }

    private func syncState(_ status: AVPlayer.TimeControlStatus) {
        switch status {
        case .playing: state = .playing
        case .waitingToPlayAtSpecifiedRate: state = .loading
        case .paused: if player.currentItem != nil && state != .loading { state = .paused }
        @unknown default: break
        }
        updateNowPlaying()
    }

    // MARK: Now Playing / media keys

    private func setupRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.addTarget { [weak self] _ in Task { @MainActor in self?.resume() }; return .success }
        commandCenter.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.pause() }; return .success }
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.toggle() }; return .success }
        commandCenter.stopCommand.addTarget { [weak self] _ in Task { @MainActor in self?.stop() }; return .success }
        commandCenter.nextTrackCommand.isEnabled = false
        commandCenter.previousTrackCommand.isEnabled = false
        commandCenter.changePlaybackPositionCommand.isEnabled = false
    }

    private func updateNowPlaying() {
        let playing = player.timeControlStatus == .playing
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title.isEmpty ? AppInfo.name : title,
            MPMediaItemPropertyArtist: streamTitle ?? URL(string: sourceURL)?.host ?? AppInfo.name,
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyPlaybackRate: playing ? 1.0 : 0.0,
        ]
        if let artwork, let image = NSImage(data: artwork) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        } else if let icon = NSApp?.applicationIconImage {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: icon.size) { _ in icon }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = playing ? .playing : (state == .idle ? .stopped : .paused)
    }
}

extension Notification.Name {
    /// Posted when a thumbnail is fetched for a URL (object: url String, userInfo["data"]: Data).
    static let airwaveArtwork = Notification.Name("airwaveArtwork")
}
