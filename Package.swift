// swift-tools-version:5.9
import PackageDescription

// Backend is chosen at build time: AIRWAVE_BACKEND=youtubekit swift build
// (make-app.sh sets this from its --backend argument). Default: yt-dlp.
let useYouTubeKit = Context.environment["AIRWAVE_BACKEND"] == "youtubekit"

let package = Package(
    name: "Airwave",
    platforms: [.macOS(.v14)],
    dependencies: useYouTubeKit
        ? [.package(url: "https://github.com/alexeichhorn/YouTubeKit", from: "0.2.0")]
        : [],
    targets: [
        .executableTarget(
            name: "Airwave",
            dependencies: useYouTubeKit ? [.product(name: "YouTubeKit", package: "YouTubeKit")] : [],
            path: "Sources/Airwave",
            swiftSettings: useYouTubeKit ? [.define("YOUTUBEKIT")] : []
        )
    ]
)
