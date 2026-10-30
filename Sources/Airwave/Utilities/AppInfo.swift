import Foundation

/// Static application identity, kept in one place for the UI, Now Playing
/// metadata and outbound network requests.
enum AppInfo {
    static let name = "Airwave"

    /// Bundle version, read from the packaged app's `Info.plist`. Falls back to
    /// `"dev"` when running unbundled (for example `swift run`). The value is
    /// written into the bundle by the `bundle` plugin from the root `VERSION`
    /// file, which is the single source of truth for the version.
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    /// User-Agent sent when probing stream/ICY endpoints.
    static var userAgent: String { "\(name)/\(version)" }
}
