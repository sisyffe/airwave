import Foundation

/// Static application identity, kept in one place for the UI, Now Playing
/// metadata and outbound network requests.
enum AppInfo {
    static let name = "Airwave"
    static let version = "1.1.0"

    /// User-Agent sent when probing stream/ICY endpoints. Note: this is kept as
    /// "Airwave/1.1" to preserve existing request behavior even though the
    /// bundle version is "1.1.0".
    static let userAgent = "Airwave/1.1"
}
