import Foundation

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

    static func shouldQuitAfterLastWindowClosed(using defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: quitOnLastWindowClosed) != nil else {
            return defaultQuitOnLastWindowClosed
        }
        return defaults.bool(forKey: quitOnLastWindowClosed)
    }
}
