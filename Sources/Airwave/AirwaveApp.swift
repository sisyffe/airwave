import SwiftUI
import AppKit

@main
struct AirwaveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var player = AudioPlayer.shared
    @StateObject private var favorites = FavoritesStore()
    @StateObject private var recents = RecentsStore.shared
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
                .environmentObject(recents)
                .frame(minWidth: 240, idealWidth: 260, minHeight: 380, idealHeight: 460)
                .onReceive(NotificationCenter.default.publisher(for: .airwaveArtwork)) { notification in
                    if let url = notification.object as? String, let data = notification.userInfo?["data"] as? Data {
                        favorites.setThumbnail(data, for: url)
                        recents.setThumbnail(data, for: url)
                    }
                }
                .task { runHotstart() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 260, height: 460)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Airwave") { appDelegate.showAbout() }
            }
            CommandMenu("Playback") {
                Button(player.isPlaying ? "Pause" : "Play") { player.toggle() }
                    .keyboardShortcut(.space, modifiers: [])
                Button("Stop") { player.stop() }
                    .keyboardShortcut(".", modifiers: .command)
                Button("Refresh") { player.refresh() }
                    .keyboardShortcut("r", modifiers: .command)
                Divider()
                // Arrow keys seek finite tracks; Shift makes the jump 30 seconds.
                // Disabled for live streams, which have no seekable timeline.
                Button("Rewind 10 Seconds") { player.skip(by: -10) }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                    .disabled(player.isLive)
                Button("Forward 10 Seconds") { player.skip(by: 10) }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                    .disabled(player.isLive)
                Button("Rewind 30 Seconds") { player.skip(by: -30) }
                    .keyboardShortcut(.leftArrow, modifiers: .shift)
                    .disabled(player.isLive)
                Button("Forward 30 Seconds") { player.skip(by: 30) }
                    .keyboardShortcut(.rightArrow, modifiers: .shift)
                    .disabled(player.isLive)
            }
        }

        Settings {
            PreferencesView()
                .environmentObject(favorites)
                .environmentObject(recents)
                .environmentObject(player)
        }
    }

    private func runHotstart() {
        guard hotstart, !AudioPlayer.shared.hasStarted, !lastURL.isEmpty else { return }
        let favorite = favorites.favorite(for: lastURL)
        Task { await AudioPlayer.shared.play(urlString: lastURL, title: favorite?.name, artwork: favorite?.thumbnail) }
    }
}

/// Closing the last window quits by default; the user can opt into macOS keep-running behavior.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        Prefs.shouldQuitAfterLastWindowClosed()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag, let window = sender.windows.first(where: { $0.title == "Airwave" && $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        }
        return true
    }

    /// Right-click Dock menu: Play/Pause plus a submenu of the last played tracks.
    @MainActor
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()

        let recentsItem = NSMenuItem(title: "Recent Tracks", action: nil, keyEquivalent: "")
        let recentsMenu = NSMenu()
        let recents = RecentsStore.shared.items
        if recents.isEmpty {
            let empty = NSMenuItem(title: "No Recent Tracks", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            recentsMenu.addItem(empty)
        } else {
            for track in recents {
                let item = NSMenuItem(title: track.name, action: #selector(dockPlayRecent(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = track.url
                item.toolTip = track.url
                recentsMenu.addItem(item)
            }
        }
        recentsItem.submenu = recentsMenu
        menu.addItem(recentsItem)

        let toggleItem = NSMenuItem(
            title: AudioPlayer.shared.isPlaying ? "Pause" : "Play",
            action: #selector(dockToggle), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)

        return menu
    }

    @objc private func dockToggle() {
        Task { @MainActor in AudioPlayer.shared.toggle() }
    }

    @objc private func dockPlayRecent(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? String else { return }
        let title = sender.title
        Task { @MainActor in await AudioPlayer.shared.play(urlString: url, title: title) }
    }

    @MainActor
    func showAbout() {
        let credits = NSAttributedString(
            string:
                "A lightweight macOS audio player for YouTube livestreams and direct audio streams. Save favorites and control playback with macOS media controls.\n\nVibe coded with Lovable and Claude.",
            attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)]
        )
        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .applicationName: AppInfo.name,
            .applicationVersion: AppInfo.version,
            .version: AppInfo.version,
            .credits: credits,
        ])
    }
}
