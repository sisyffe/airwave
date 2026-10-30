// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Airwave",
    platforms: [.macOS(.v14)],
    dependencies: [.package(url: "https://github.com/alexeichhorn/YouTubeKit", from: "0.4.10")],
    targets: [
        .executableTarget(
            name: "Airwave",
            dependencies: [.product(name: "YouTubeKit", package: "YouTubeKit")],
            path: "Sources/Airwave"
        ),
        .plugin(
            name: "BundleApp",
            capability: .command(
                intent: .custom(verb: "bundle", description: "Build a release Airwave.app into dist/"),
                permissions: [.writeToPackageDirectory(reason: "Writes the packaged Airwave.app to dist/")]
            ),
            path: "Plugins/BundleApp"
        )
    ]
)
