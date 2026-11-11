import Foundation
import AVFoundation
import MediaPlayer
import AppKit
import Combine

/// AVPlayer wrapper that publishes state and integrates with macOS Now Playing
/// (Control Center, media keys, AirPods, Touch Bar, lock screen).
@MainActor
final class AudioPlayer: ObservableObject {
    static let shared = AudioPlayer()

    enum State: Equatable { case idle, loading, playing, paused }

    @Published private(set) var state: State = .idle
    /// The track being played; its identity is shared with favorites and recents.
    @Published private(set) var track: Track?
    /// Thumbnail of the current track (PNG data from `ThumbnailStore`), if any.
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

    var title: String { track?.name ?? "" }
    var sourceURL: String { track?.url ?? "" }

    private(set) var hasStarted = false
    private var librarySync: AnyCancellable?
    private let player = AVPlayer()
    private var statusObservation: NSKeyValueObservation?
    private var rateObservation: NSKeyValueObservation?
    /// Tracks the current item's duration so `isLive` stays accurate.
    private var durationObservation: NSKeyValueObservation?
    /// Trim offsets for the current favorite, applied once the item is known to
    /// be finite: `trimStartOffset` from the start, `trimEndOffset` back from the
    /// end. Nil means no trim.
    private var trimStartOffset: TimeInterval?
    private var trimEndOffset: TimeInterval?
    private var trimApplied = false
    /// Set while a replay seek is in flight, so end signals raised meanwhile are ignored.
    private var isReplaying = false
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
        librarySync = TrackLibrary.shared.$catalog.sink { [weak self] catalog in
            Task { @MainActor in self?.adoptStoredCopy(from: catalog) }
        }
        rateObservation = player.observe(\.timeControlStatus) { [weak self] player, _ in
            Task { @MainActor in self?.syncState(player.timeControlStatus) }
        }
    }

    // MARK: Playback

    /// What was playing before a new track was requested, so it can be restored
    /// when the new one fails to load.
    private struct Snapshot {
        let track: Track?
        let artwork: Data?
        let item: AVPlayerItem?
        let wasPlaying: Bool
        let trimStartOffset: TimeInterval?
        let trimEndOffset: TimeInterval?
    }

    /// Plays a track by id from the library; alerts when it no longer exists.
    func play(id: UUID) async {
        guard let stored = TrackLibrary.shared.track(id) else {
            lastError = "That track is no longer in your library."
            return
        }
        await play(stored)
    }

    func play(_ requested: Track) async {
        hasStarted = true
        lastError = nil
        let playGeneration = generation.begin()
        let previous = Snapshot(
            track: track, artwork: artwork, item: player.currentItem, wasPlaying: isPlaying,
            trimStartOffset: trimStartOffset, trimEndOffset: trimEndOffset)
        // The library copy wins so trim and cover edits are always honored.
        let target = TrackLibrary.shared.track(requested.id) ?? requested
        trimStartOffset = target.startOffset
        trimEndOffset = target.endOffset
        trimApplied = false
        beginLoading(target)
        do {
            let resolved = try await StreamResolver.resolve(target.url)
            guard generation.isCurrent(playGeneration) else { return }  // user switched or stopped
            var playing = track ?? target
            playing.isDirect = resolved.isDirect
            if playing.name == playing.url, let resolvedTitle = resolved.title { playing.name = resolvedTitle }
            track = playing
            start(resolved, previous: previous, playGeneration: playGeneration)
            await refreshArtwork(resolved, playGeneration: playGeneration)
        } catch {
            guard generation.isCurrent(playGeneration) else { return }  // a newer link owns the UI
            restore(previous)  // keep whatever was playing…
            lastError = error.localizedDescription  // …and surface the problem as an alert
        }
    }

    /// Resets published state for a new track before its stream is resolved.
    private func beginLoading(_ target: Track) {
        state = .loading
        streamTitle = nil
        isLive = true
        icyTask?.cancel()
        icyTask = nil
        removeEndOfTrackObserver()
        removeDurationObserver()
        track = target
        artwork = ThumbnailStore.data(for: target.thumbnailKey)
        updateNowPlaying()
    }

    /// Swaps in the resolved stream, starts playback and wires up failure handling.
    private func start(_ resolved: StreamResolver.Resolved, previous: Snapshot, playGeneration: Int) {
        let item = makePlayerItem(for: resolved)
        statusObservation = item.observe(\.status) { [weak self] item, _ in
            Task { @MainActor in
                guard let self, item.status == .failed, self.generation.isCurrent(playGeneration) else { return }
                self.itemFailed(item, previous: previous)
            }
        }
        if let track {
            TrackLibrary.shared.recordPlayback(track)
            UserDefaultsJSON.save(track, to: Prefs.lastTrack)
        }
        observeEndOfTrack(of: item)
        player.replaceCurrentItem(with: item)
        observeDuration(of: item)
        player.play()
        updateNowPlaying()
        startICYIfEligible(resolved, playGeneration: playGeneration)
    }

    private func makePlayerItem(for resolved: StreamResolver.Resolved) -> AVPlayerItem {
        // Apply stream-specific headers when supplied by the resolver.
        var options: [String: Any] = [:]
        if !resolved.headers.isEmpty { options["AVURLAssetHTTPHeaderFieldsKey"] = resolved.headers }
        return AVPlayerItem(asset: AVURLAsset(url: resolved.streamURL, options: options))
    }

    /// Refreshes the automatic artwork on every play, for every non-custom track
    /// sharing the link. Custom covers are never replaced.
    private func refreshArtwork(_ resolved: StreamResolver.Resolved, playGeneration: Int) async {
        guard let current = track, !current.hasCustomThumbnail else { return }
        let fetched = await StreamResolver.fetchThumbnail(resolved.thumbnailURL, page: current.url)
        guard generation.isCurrent(playGeneration), let fetched, let key = ThumbnailStore.save(fetched) else { return }
        TrackLibrary.shared.applyThumbnail(key, forURL: current.url)
    }

    /// Mirrors the library's copy of the playing track (rename, cover, finiteness).
    /// Trim already applied to the running item is left alone until the next play.
    private func adoptStoredCopy(from catalog: TrackCatalog) {
        guard let current = track, let stored = catalog.tracks[current.id], stored != current else { return }
        let keyChanged = stored.thumbnailKey != current.thumbnailKey
        track = stored
        if keyChanged { artwork = ThumbnailStore.data(for: stored.thumbnailKey) }
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
        isReplaying = false
        if let item = snapshot.item, player.currentItem !== item {
            player.replaceCurrentItem(with: item)
            if item.duration.isIndefinite {
                item.seek(to: .positiveInfinity, completionHandler: nil)  // back to the live edge
            }
        }
        // Set the track first so the duration observer records finiteness for the
        // restored track, not the one that just failed.
        track = snapshot.track
        if let item = snapshot.item {
            observeDuration(of: item)
            observeEndOfTrack(of: item)
        }
        if snapshot.wasPlaying, snapshot.item != nil { player.play() }
        artwork = snapshot.artwork
        isLive = snapshot.item?.duration.isIndefinite ?? true
        state = snapshot.item == nil ? .idle : (snapshot.wasPlaying ? .playing : .paused)
        if let track = snapshot.track {
            UserDefaultsJSON.save(track, to: Prefs.lastTrack)
        }
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
            // Learn that this track is finite, so its favorite can offer trim.
            if let id = track?.id {
                track?.isFinite = true
                TrackLibrary.shared.setFinite(id, true)
            }
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
                // AVFoundation stops at this time and posts didPlayToEnd, the only end signal.
                item.forwardPlaybackEndTime = CMTime(seconds: end, preferredTimescale: 600)
            }
        }
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

    /// Replays or stops a finished track, per the Playback setting. Signals that
    /// arrive while a replay is in flight, or before the playhead has reached the
    /// effective end, are stale and ignored.
    private func trackDidReachEnd() {
        guard !isReplaying, let item = player.currentItem, !item.duration.isIndefinite else { return }
        let effectiveEnd = item.duration.seconds - (trimEndOffset ?? 0)
        guard player.currentTime().seconds >= effectiveEnd - Self.endTolerance else { return }
        guard Prefs.shouldReplayOnTrackEnd() else {
            stop()
            return
        }
        isReplaying = true
        let start = CMTime(seconds: trimStartOffset ?? 0, preferredTimescale: 600)
        player.seek(to: start, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.isReplaying = false
                self.player.play()
            }
        }
    }

    /// Slack allowed between the playhead and the effective end when accepting an end signal.
    private static let endTolerance: TimeInterval = 0.5

    func resume() {
        guard player.currentItem != nil else {
            if let track { Task { await play(track) } }
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
        guard let track else { return }
        Task { await play(track) }
    }

    func stop() {
        // Invalidate in-flight work so a stream still resolving (or artwork still
        // downloading) cannot start playback or paint artwork after the stop.
        generation.invalidate()
        removeEndOfTrackObserver()
        removeDurationObserver()
        trimStartOffset = nil
        trimEndOffset = nil
        trimApplied = false
        player.pause()
        player.replaceCurrentItem(with: nil)
        icyTask?.cancel()
        icyTask = nil
        streamTitle = nil
        isLive = true
        track = nil
        artwork = nil
        state = .idle
        // Forget the resume URL so hotstart does not restart a stopped stream.
        UserDefaults.standard.removeObject(forKey: Prefs.lastTrack)
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
                if let station = info.station, let id = self.track?.id {
                    TrackLibrary.shared.adoptStationName(id, station)
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
