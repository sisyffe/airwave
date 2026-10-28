import SwiftUI
import AppKit

@main
struct AirwaveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var player = AudioPlayer.shared
    @StateObject private var favorites = FavoritesStore()
    @AppStorage(Prefs.hotstart) private var hotstart = true
    @AppStorage(Prefs.lastURL) private var lastURL = ""

    init() {
        // Needed when launched via `swift run` (no bundle Info.plist).
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup("Airwave", id: "main") {
            ContentView()
                .environmentObject(player)
                .environmentObject(favorites)
                .frame(minWidth: 240, idealWidth: 260, maxWidth: 360, minHeight: 380, idealHeight: 460)
                .onReceive(NotificationCenter.default.publisher(for: .airwaveArtwork)) { n in
                    if let url = n.object as? String, let data = n.userInfo?["data"] as? Data {
                        favorites.setThumbnail(data, for: url)
                    }
                }
                .task { runHotstart() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 260, height: 460)
        .windowResizability(.contentMinSize)
        .commands {
            CommandMenu("Playback") {
                Button(player.isPlaying ? "Pause" : "Play") { player.toggle() }
                    .keyboardShortcut(.space, modifiers: [])
                Button("Stop") { player.stop() }
                    .keyboardShortcut(".", modifiers: .command)
            }
        }

        Settings {
            PreferencesView()
                .environmentObject(favorites)
        }
    }

    private func runHotstart() {
        guard hotstart, !AudioPlayer.shared.hasStarted, !lastURL.isEmpty else { return }
        let fav = favorites.favorite(for: lastURL)
        Task { await AudioPlayer.shared.play(urlString: lastURL, title: fav?.name, artwork: fav?.thumbnail) }
    }
}

/// Regular app behaviour: Airwave quits when its last window is closed,
/// even if audio is still playing.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
