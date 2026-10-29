import Foundation

enum Prefs {
    static let hotstart = "hotstart"
    static let lastURL = "lastURL"
    static let volume = "volume"
    static let quitOnLastWindowClosed = "quitOnLastWindowClosed"
    static let defaultQuitOnLastWindowClosed = true

    static func shouldQuitAfterLastWindowClosed(using defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: quitOnLastWindowClosed) != nil else {
            return defaultQuitOnLastWindowClosed
        }
        return defaults.bool(forKey: quitOnLastWindowClosed)
    }
}
