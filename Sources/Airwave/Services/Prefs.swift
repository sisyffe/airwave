import Foundation

/// How thumbnail artwork is fitted into its square frame.
enum ThumbnailDisplayMode: String, CaseIterable, Identifiable {
    /// Crop to fill the square (the default).
    case fill
    /// Letterbox the whole image inside the square.
    case fit
    /// Fit the whole image over a blurred, cropped copy of itself.
    case blurredFill

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fill: return "Fill"
        case .fit: return "Fit"
        case .blurredFill: return "Blurred fill"
        }
    }
}

enum Prefs {
    static let hotstart = "hotstart"
    static let lastURL = "lastURL"
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
    static let thumbnailDisplayMode = "thumbnailDisplayMode"
    static let defaultThumbnailDisplayMode = ThumbnailDisplayMode.fill

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

    /// The stored thumbnail display mode, falling back to the default when unset
    /// or unrecognized.
    static func thumbnailDisplayMode(using defaults: UserDefaults = .standard) -> ThumbnailDisplayMode {
        guard let raw = defaults.string(forKey: thumbnailDisplayMode),
            let mode = ThumbnailDisplayMode(rawValue: raw)
        else { return defaultThumbnailDisplayMode }
        return mode
    }
}
