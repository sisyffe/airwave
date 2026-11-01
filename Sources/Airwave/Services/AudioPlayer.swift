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
    /// Whether the current item has no known end (live stream / endless radio).
    @Published private(set) var isLive = true
    @Published var volume: Float {
        didSet { player.volume = volume; UserDefaults.standard.set(volume, forKey: Prefs.volume) }
    }

    private(set) var hasStarted = false
    private let player = AVPlayer()
    private var statusObservation: NSKeyValueObservation?
    private var rateObservation: NSKeyValueObservation?
    /// Tracks the current item's duration so `isLive` stays accurate.
    private var durationObservation: NSKeyValueObservation?
    /// True when `artwork` was supplied by the user, so automatic fetching must
    /// not replace it on the Now Playing card.
    private var artworkIsCustom = false
    /// Trim offsets for the current favorite, applied once the item is known to
    /// be finite: `trimStartOffset` from the start, `trimEndOffset` back from the
    /// end. Nil means no trim.
    private var trimStartOffset: TimeInterval?
    private var trimEndOffset: TimeInterval?
    private var trimApplied = false
    /// Boundary observer that fires when playback crosses the trimmed end.
    private var trimEndObserver: Any?
    /// Fires when the current finite item reaches its end, to replay or stop it.
    private var endOfTrackObserver: NSObjectProtocol?
    /// ICY metadata reader task for the current direct stream, if any.
    private var icyTask: Task<Void, Never>?
    /// Guards async playback work; stale work is dropped if the token is no
    /// longer current (a newer play, or a stop).
    private var generation = PlaybackGeneration()

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
        let artworkIsCustom: Bool
        let item: AVPlayerItem?
        let wasPlaying: Bool
        let trimStartOffset: TimeInterval?
        let trimEndOffset: TimeInterval?
    }

    func play(urlString: String, title: String? = nil, artwork knownArtwork: Data? = nil, customArtwork: Bool = false) async {
        hasStarted = true
        lastError = nil
        let playGeneration = generation.begin()
        let previous = Snapshot(
            url: sourceURL, title: self.title, artwork: artwork, artworkIsCustom: artworkIsCustom,
            item: player.currentItem, wasPlaying: isPlaying, trimStartOffset: trimStartOffset,
            trimEndOffset: trimEndOffset)
        artworkIsCustom = customArtwork
        // A favorite may define a trim range; it applies wherever the URL plays.
        let favorite = FavoritesStore.shared.favorite(for: urlString)
        trimStartOffset = favorite?.startOffset
        trimEndOffset = favorite?.endOffset
        trimApplied = false
        removeTrimEndObserver()
        beginLoading(urlString: urlString, title: title, artwork: knownArtwork)
        do {
            let resolved = try await StreamResolver.resolve(urlString)
            guard generation.isCurrent(playGeneration) else { return }  // user switched or stopped
            if title == nil, let resolvedTitle = resolved.title { self.title = resolvedTitle }
            start(resolved, urlString: urlString, previous: previous, playGeneration: playGeneration)
            await refreshArtwork(resolved, page: urlString, playGeneration: playGeneration)
        } catch {
            guard generation.isCurrent(playGeneration) else { return }  // a newer link owns the UI
            restore(previous)  // keep whatever was playing…
            lastError = error.localizedDescription  // …and surface the problem as an alert
        }
    }

    /// Resets published state for a new link before its stream is resolved.
    private func beginLoading(urlString: String, title: String?, artwork knownArtwork: Data?) {
        state = .loading
        streamTitle = nil
        isLive = true
        icyTask?.cancel()
        icyTask = nil
        removeEndOfTrackObserver()
        removeDurationObserver()
        sourceURL = urlString
        self.title = title ?? urlString
        artwork = knownArtwork
        updateNowPlaying()
    }

    /// Swaps in the resolved stream, starts playback and wires up failure handling.
    private func start(_ resolved: StreamResolver.Resolved, urlString: String, previous: Snapshot, playGeneration: Int) {
        let item = makePlayerItem(for: resolved)
        statusObservation = item.observe(\.status) { [weak self] item, _ in
            Task { @MainActor in
                guard let self, item.status == .failed, self.generation.isCurrent(playGeneration) else { return }
                self.itemFailed(item, previous: previous)
            }
        }
        observeEndOfTrack(of: item)
        player.replaceCurrentItem(with: item)
        observeDuration(of: item)
        player.play()
        UserDefaults.standard.set(urlString, forKey: Prefs.lastURL)
        RecentsStore.shared.record(name: self.title, url: urlString, thumbnail: artwork, custom: artworkIsCustom)
        updateNowPlaying()
        startICYIfEligible(resolved, playGeneration: playGeneration)
    }

    private func makePlayerItem(for resolved: StreamResolver.Resolved) -> AVPlayerItem {
        // Apply stream-specific headers when supplied by the resolver.
        var options: [String: Any] = [:]
        if !resolved.headers.isEmpty { options["AVURLAssetHTTPHeaderFieldsKey"] = resolved.headers }
        return AVPlayerItem(asset: AVURLAsset(url: resolved.streamURL, options: options))
    }

    /// Refreshes the artwork even when a cached one was supplied (from
    /// favorites/recents), so covers stay up to date on every play.
    private func refreshArtwork(_ resolved: StreamResolver.Resolved, page: String, playGeneration: Int) async {
        guard !artworkIsCustom else { return }  // keep the user's cover
        let fetched = await StreamResolver.fetchThumbnail(resolved.thumbnailURL, page: page)
        if generation.isCurrent(playGeneration), let fetched, fetched != artwork {
            artwork = fetched
            updateNowPlaying()
            NotificationCenter.default.post(name: .airwaveArtwork, object: page, userInfo: ["data": fetched])
        }
    }

    /// Replaces the artwork of the currently playing track (used when a custom
    /// thumbnail is set or reset from Settings). No-op for other URLs.
    func applyArtwork(_ data: Data?, for url: String, custom: Bool) {
        guard url == sourceURL else { return }
        artwork = data
        artworkIsCustom = custom
        updateNowPlaying()
    }

    /// The item we just swapped in never actually started; put back what was playing before.
    private func itemFailed(_ item: AVPlayerItem, previous: Snapshot) {
        let message = item.error?.localizedDescription ?? "Playback failed"
        if case .loading = state { restore(previous) }
        lastError = message
    }

    private func restore(_ snapshot: Snapshot) {
        removeEndOfTrackObserver()
        removeDurationObserver()
        // Restore trim before the duration observer runs, so it re-applies for
        // the item being brought back.
        trimStartOffset = snapshot.trimStartOffset
        trimEndOffset = snapshot.trimEndOffset
        trimApplied = false
        removeTrimEndObserver()
        if let item = snapshot.item, player.currentItem !== item {
            player.replaceCurrentItem(with: item)
            if item.duration.isIndefinite {
                item.seek(to: .positiveInfinity, completionHandler: nil)  // back to the live edge
            }
        }
        // Set the URL first so the duration observer records finiteness for the
        // restored track, not the one that just failed.
        sourceURL = snapshot.url
        if let item = snapshot.item {
            observeDuration(of: item)
            observeEndOfTrack(of: item)
        }
        if snapshot.wasPlaying, snapshot.item != nil { player.play() }
        title = snapshot.title
        artwork = snapshot.artwork
        artworkIsCustom = snapshot.artworkIsCustom
        isLive = snapshot.item?.duration.isIndefinite ?? true
        state = snapshot.item == nil ? .idle : (snapshot.wasPlaying ? .playing : .paused)
        updateNowPlaying()
    }

    /// Observes the current item's duration so `isLive` reflects whether the
    /// track has an end (finite audio) or is an endless stream.
    private func observeDuration(of item: AVPlayerItem) {
        durationObservation = item.observe(\.duration) { [weak self] item, _ in
            Task { @MainActor in self?.updateLiveState(item) }
        }
        updateLiveState(item)
    }

    private func removeDurationObserver() {
        durationObservation = nil
    }

    private func updateLiveState(_ item: AVPlayerItem) {
        guard player.currentItem === item else { return }
        isLive = item.duration.isIndefinite
        if !isLive {
            applyTrimIfNeeded(item)
            // Learn that this URL is a finite track, so its favorite can offer trim.
            FavoritesStore.shared.setFinite(true, for: sourceURL)
        }
    }

    /// Applies the favorite's trim once the item is known to be finite: seek to
    /// the start offset and cap forward playback `endOffset` seconds before the
    /// track's natural end.
    private func applyTrimIfNeeded(_ item: AVPlayerItem) {
        guard !trimApplied, trimStartOffset != nil || trimEndOffset != nil else { return }
        trimApplied = true
        if let start = trimStartOffset, start > 0 {
            player.seek(to: CMTime(seconds: start, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        }
        let duration = item.duration.seconds
        if let offset = trimEndOffset, offset > 0, duration.isFinite {
            let end = duration - offset
            if end > (trimStartOffset ?? 0) {
                item.forwardPlaybackEndTime = CMTime(seconds: end, preferredTimescale: 600)
                installTrimEndObserver(end)
            }
        }
    }

    private func installTrimEndObserver(_ end: TimeInterval) {
        removeTrimEndObserver()
        let time = NSValue(time: CMTime(seconds: end, preferredTimescale: 600))
        trimEndObserver = player.addBoundaryTimeObserver(forTimes: [time], queue: .main) { [weak self] in
            Task { @MainActor in self?.trimDidReachEnd() }
        }
    }

    private func removeTrimEndObserver() {
        if let trimEndObserver {
            player.removeTimeObserver(trimEndObserver)
            self.trimEndObserver = nil
        }
    }

    /// The trimmed end was reached: replay from the trim start or stop.
    private func trimDidReachEnd() {
        guard !isLive else { return }
        trackDidReachEnd()
    }

    /// Watches for the end of the current item. Only finite items post this
    /// notification, so live streams are unaffected.
    private func observeEndOfTrack(of item: AVPlayerItem) {
        removeEndOfTrackObserver()
        endOfTrackObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.trackDidReachEnd() }
        }
    }

    private func removeEndOfTrackObserver() {
        if let endOfTrackObserver {
            NotificationCenter.default.removeObserver(endOfTrackObserver)
            self.endOfTrackObserver = nil
        }
    }

    /// Replays or stops a finished track, per the Playback setting.
    private func trackDidReachEnd() {
        guard let item = player.currentItem, !item.duration.isIndefinite else { return }
        if Prefs.shouldReplayOnTrackEnd() {
            player.seek(to: CMTime(seconds: trimStartOffset ?? 0, preferredTimescale: 600))
            player.play()
        } else {
            stop()
        }
    }

    func resume() {
        guard player.currentItem != nil else {
            if !sourceURL.isEmpty {
                Task { await play(urlString: sourceURL, title: title, artwork: artwork, customArtwork: artworkIsCustom) }
            }
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

    /// Jumps forward (positive) or backward (negative) by `seconds`, clamped to
    /// the track. No-op for live streams, which have no seekable timeline.
    func skip(by seconds: TimeInterval) {
        guard !isLive, let item = player.currentItem else { return }
        let duration = item.duration.seconds
        guard duration.isFinite, duration > 0 else { return }
        let lower = trimStartOffset ?? 0
        let upper = min(duration - (trimEndOffset ?? 0), duration)
        let target = min(max(player.currentTime().seconds + seconds, lower), upper)
        player.seek(
            to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// Re-resolve and reload the current source (fresh stream URL), keeping the
    /// existing title and artwork so the UI does not flicker.
    func refresh() {
        guard !sourceURL.isEmpty else { return }
        Task { await play(urlString: sourceURL, title: title, artwork: artwork, customArtwork: artworkIsCustom) }
    }

    func stop() {
        // Invalidate in-flight work so a stream still resolving (or artwork still
        // downloading) cannot start playback or paint artwork after the stop.
        generation.invalidate()
        removeEndOfTrackObserver()
        removeDurationObserver()
        removeTrimEndObserver()
        trimStartOffset = nil
        trimEndOffset = nil
        trimApplied = false
        player.pause()
        player.replaceCurrentItem(with: nil)
        icyTask?.cancel()
        icyTask = nil
        streamTitle = nil
        isLive = true
        artworkIsCustom = false
        sourceURL = ""
        title = ""
        artwork = nil
        state = .idle
        // Forget the resume URL so hotstart does not restart a stopped stream.
        UserDefaults.standard.removeObject(forKey: Prefs.lastURL)
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
                guard let self, self.generation.isCurrent(playGeneration) else { return }
                if let station = info.station, self.title == self.sourceURL {
                    self.title = station
                    RecentsStore.shared.record(name: station, url: self.sourceURL, thumbnail: self.artwork, custom: self.artworkIsCustom)
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
        commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }; return .success
        }
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }; return .success
        }
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.toggle() }; return .success
        }
        commandCenter.stopCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.stop() }; return .success
        }
        commandCenter.nextTrackCommand.isEnabled = false
        commandCenter.previousTrackCommand.isEnabled = false
        commandCenter.changePlaybackPositionCommand.isEnabled = false
    }

    private func updateNowPlaying() {
        let playing = player.timeControlStatus == .playing
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title.isEmpty ? AppInfo.name : title,
            MPMediaItemPropertyArtist: streamTitle ?? URL(string: sourceURL)?.host ?? AppInfo.name,
            MPNowPlayingInfoPropertyIsLiveStream: isLive,
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
