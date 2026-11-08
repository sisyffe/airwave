import Foundation

enum Prefs {
    static let hotstart = "hotstart"
    /// The last track that was playing, stored whole so hotstart restores it.
    static let lastTrack = "lastTrack"
    static let volume = "volume"
    static let defaultVolume: Float = 0.75
    static let trackLibrary = "trackLibrary"
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
    static let manualLinkMode = "manualLinkMode"

    static func shouldQuitAfterLastWindowClosed(using defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: quitOnLastWindowClosed) != nil else {
            return defaultQuitOnLastWindowClosed
        }
        return defaults.bool(forKey: quitOnLastWindowClosed)
    }

    /// Whether a finished finite track should replay instead of stopping.
    static func shouldReplayOnTrackEnd(using defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: replayOnTrackEnd) != nil else {
            return defaultReplayOnTrackEnd
        }
        return defaults.bool(forKey: replayOnTrackEnd)
    }

    static func manualLinkMode(using defaults: UserDefaults = .standard) -> ManualLinkMode {
        defaults.string(forKey: manualLinkMode).flatMap(ManualLinkMode.init(rawValue:)) ?? .defaultMode
    }
}
