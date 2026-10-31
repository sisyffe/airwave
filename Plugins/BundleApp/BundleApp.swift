import Foundation
import PackagePlugin

/// `swift package bundle` — packages the release binary as `dist/Airwave.app`
/// with an ad-hoc code signature.
///
/// Build first, then bundle:
///
///     swift build -c release
///     swift package --allow-writing-to-package-directory bundle
///
/// The bundle version is read from the repository's `VERSION` file, the single
/// source of truth for the app version (the app reads it back at runtime from
/// `CFBundleShortVersionString`).
@main
struct BundleApp: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        let packageDirectory = URL(fileURLWithPath: context.package.directory.string)
        let version = try readVersion(in: packageDirectory)
        let executable = packageDirectory.appendingPathComponent(".build/release/Airwave")
        guard FileManager.default.fileExists(atPath: executable.path) else {
            throw BundleError.missingBinary(executable.path)
        }

        print("Bundling Airwave \(version)")

        let bundle = try makeBundle(in: packageDirectory, version: version)
        try copyExecutable(executable, into: bundle)
        try copyIcon(from: packageDirectory, into: bundle)
        try sign(bundle)

        print("Built \(bundle.path) — drag it to /Applications.")
    }

    // MARK: Steps

    private func readVersion(in packageDirectory: URL) throws -> String {
        let versionFile = packageDirectory.appendingPathComponent("VERSION")
        let raw = try String(contentsOf: versionFile, encoding: .utf8)
        let version = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !version.isEmpty else { throw BundleError.missingVersion }
        return version
    }

    private func makeBundle(in packageDirectory: URL, version: String) throws -> URL {
        let fileManager = FileManager.default
        let bundle = packageDirectory.appendingPathComponent("dist/Airwave.app")
        if fileManager.fileExists(atPath: bundle.path) {
            try fileManager.removeItem(at: bundle)
        }

        let contents = bundle.appendingPathComponent("Contents")
        try fileManager.createDirectory(
            at: contents.appendingPathComponent("MacOS"),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: contents.appendingPathComponent("Resources"),
            withIntermediateDirectories: true
        )
        try infoPlist(version: version).write(
            to: contents.appendingPathComponent("Info.plist"),
            atomically: true,
            encoding: .utf8
        )
        return bundle
    }

    private func copyExecutable(_ executable: URL, into bundle: URL) throws {
        try FileManager.default.copyItem(
            at: executable,
            to: bundle.appendingPathComponent("Contents/MacOS/Airwave")
        )
    }

    private func copyIcon(from packageDirectory: URL, into bundle: URL) throws {
        let icon = packageDirectory.appendingPathComponent("Resources/AppIcon.icns")
        guard FileManager.default.fileExists(atPath: icon.path) else { return }
        try FileManager.default.copyItem(
            at: icon,
            to: bundle.appendingPathComponent("Contents/Resources/AppIcon.icns")
        )
    }

    private func sign(_ bundle: URL) throws {
        try run(["/usr/bin/codesign", "--force", "--sign", "-", bundle.path], in: bundle)
    }

    private func infoPlist(version: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
          <key>CFBundleName</key><string>Airwave</string>
          <key>CFBundleIdentifier</key><string>com.example.airwave</string>
          <key>CFBundleExecutable</key><string>Airwave</string>
          <key>CFBundlePackageType</key><string>APPL</string>
          <key>CFBundleIconFile</key><string>AppIcon</string>
          <key>CFBundleShortVersionString</key><string>\(version)</string>
          <key>CFBundleVersion</key><string>\(version)</string>
          <key>LSMinimumSystemVersion</key><string>13.0</string>
          <key>NSHighResolutionCapable</key><true/>
          <key>NSAppTransportSecurity</key><dict><key>NSAllowsArbitraryLoads</key><true/></dict>
        </dict></plist>
        """
    }

    // MARK: Process helpers

    private func run(_ arguments: [String], in workingDirectory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw BundleError.commandFailed(arguments, process.terminationStatus)
        }
    }
}

enum BundleError: Error, CustomStringConvertible {
    case missingVersion
    case missingBinary(String)
    case commandFailed([String], Int32)

    var description: String {
        switch self {
        case .missingVersion:
            return "VERSION file is missing or empty."
        case .missingBinary(let path):
            return "Release binary not found at \(path). Run `swift build -c release` first."
        case .commandFailed(let arguments, let status):
            return "Command failed (\(status)): \(arguments.joined(separator: " "))"
        }
    }
}
