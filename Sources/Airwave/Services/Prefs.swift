import Foundation

/// How artwork fills its square: cropped to fill, or the whole image shown over
/// a blurred copy of itself.
enum ThumbnailDisplayMode: String, CaseIterable {
    case fill
    case fit
}

enum Prefs {
    static let hotstart = "hotstart"
    static let lastURL = "lastURL"
    static let lastTrackID = "lastTrackID"
    static let manualLinkBehavior = "manualLinkBehavior"
    static let autoRefreshSeconds = "autoRefreshSeconds"
    /// Seconds a load may take before it is restarted. Zero means never.
    static let defaultAutoRefreshSeconds: Double = 4
    static let autoRefreshStops: [Double] = [2, 3, 4, 6, 8, 10, 0]
    static let thumbnailDisplayMode = "thumbnailDisplayMode"
    static let defaultThumbnailDisplayMode = ThumbnailDisplayMode.fill
    static let defaultManualLinkBehavior = ManualLinkBehavior.playMatchingFavorite
    static let volume = "volume"
    static let defaultVolume: Float = 0.75
    static let favorites = "favorites"
    static let recentTracks = "recentTracks"
    static let recentMaxCount = "recentMaxCount"
    static let defaultRecentMaxCount = 5
    static let minRecentMaxCount = 1
    static let maxRecentMaxCount = 20
    static let quitOnLastWindowClosed = "quitOnLastWindowClosed"
    static let defaultQuitOnLastWindowClosed = true
    static let replayOnTrackEnd = "replayOnTrackEnd"
    static let defaultReplayOnTrackEnd = true
    static let showExtraSeekControls = "showExtraSeekControls"
    static let defaultShowExtraSeekControls = false

    static func shouldQuitAfterLastWindowClosed(using defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: quitOnLastWindowClosed) != nil else {
            return defaultQuitOnLastWindowClosed
        }
        return defaults.bool(forKey: quitOnLastWindowClosed)
    }

    static func manualLinkBehavior(using defaults: UserDefaults = .standard) -> ManualLinkBehavior {
        defaults.string(forKey: manualLinkBehavior).flatMap(ManualLinkBehavior.init(rawValue:))
            ?? defaultManualLinkBehavior
    }

    /// The slow-load threshold in seconds, or nil when auto-refresh is off.
    static func autoRefreshThreshold(using defaults: UserDefaults = .standard) -> Double? {
        let seconds =
            defaults.object(forKey: autoRefreshSeconds) == nil
            ? defaultAutoRefreshSeconds : defaults.double(forKey: autoRefreshSeconds)
        return seconds > 0 ? seconds : nil
    }

    /// Whether a finished finite track should replay instead of stopping.
    static func shouldReplayOnTrackEnd(using defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: replayOnTrackEnd) != nil else {
            return defaultReplayOnTrackEnd
        }
        return defaults.bool(forKey: replayOnTrackEnd)
    }
}
