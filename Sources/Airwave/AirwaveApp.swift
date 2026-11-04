import SwiftUI
import AppKit

@main
struct AirwaveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var player = AudioPlayer.shared
    @StateObject private var favorites = FavoritesStore.shared
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
        Task {
            await AudioPlayer.shared.play(
                urlString: lastURL, title: favorite?.name, artwork: favorite?.thumbnail,
                customArtwork: favorite?.hasCustomThumbnail == true)
        }
    }
}

/// Closing the last window quits by default; the user can opt into macOS keep-running behavior.
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    /// Disables the app's shortcuts while a text field is being edited, so the
    /// standard ⌘C/⌘V/⌘↑/⌘↓ editing behavior wins.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        !(NSApp.keyWindow?.firstResponder is NSTextView)
    }

    /// Drops thumbnail resources no longer referenced by any favorite or recent
    /// entry, once both stores have loaded.
    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        let keys =
            Set(FavoritesStore.shared.items.compactMap(\.thumbnailKey))
            .union(RecentsStore.shared.items.compactMap(\.thumbnailKey))
        ThumbnailCache.prune(keeping: keys)
        installControlsMenu()
    }

    // MARK: Shortcuts

    /// Installs the app's keyboard shortcuts as AppKit menu items. They are
    /// disabled while a text field is first responder, so ⌘C/⌘V/⌘↑/⌘↓ keep their
    /// standard text-editing behavior.
    @MainActor
    private func installControlsMenu() {
        guard let mainMenu = NSApp.mainMenu, mainMenu.item(withTitle: "Controls") == nil else { return }
        let menu = NSMenu(title: "Controls")
        menu.addItem(item("Toggle Favorite", #selector(toggleFavorite), "f"))
        menu.addItem(item("Copy Current Link", #selector(copyCurrentLink), "c"))
        menu.addItem(item("Paste and Play", #selector(pasteAndPlay), "v"))
        menu.addItem(.separator())
        menu.addItem(item("Volume Up", #selector(volumeUp), String(UnicodeScalar(NSUpArrowFunctionKey)!)))
        menu.addItem(item("Volume Down", #selector(volumeDown), String(UnicodeScalar(NSDownArrowFunctionKey)!)))

        let root = NSMenuItem(title: "Controls", action: nil, keyEquivalent: "")
        root.submenu = menu
        let index = mainMenu.item(withTitle: "Playback").map { mainMenu.index(of: $0) + 1 } ?? mainMenu.numberOfItems
        mainMenu.insertItem(root, at: index)
    }

    private func item(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.keyEquivalentModifierMask = .command
        return item
    }

    @objc private func toggleFavorite() {
        NotificationCenter.default.post(name: .airwaveToggleFavorite, object: nil)
    }

    @objc private func copyCurrentLink() {
        Task { @MainActor in
            let url = AudioPlayer.shared.sourceURL
            if !url.isEmpty { Clipboard.copy(url) }
        }
    }

    @objc private func pasteAndPlay() {
        Task { @MainActor in
            guard let pasted = Clipboard.string,
                let token = pasted.split(whereSeparator: \.isWhitespace).first,
                URLValidation.httpURL(from: String(token)) != nil
            else { return }
            let url = String(token)
            let favorite = FavoritesStore.shared.favorite(for: url)
            await AudioPlayer.shared.play(
                urlString: url, title: favorite?.name, artwork: favorite?.thumbnail,
                customArtwork: favorite?.hasCustomThumbnail == true, favoriteID: favorite?.id)
        }
    }

    @objc private func volumeUp() {
        Task { @MainActor in AudioPlayer.shared.stepVolume(up: true) }
    }

    @objc private func volumeDown() {
        Task { @MainActor in AudioPlayer.shared.stepVolume(up: false) }
    }

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
            for (index, track) in recents.enumerated() {
                let item = NSMenuItem(
                    title: "\(index + 1). \(track.name)", action: #selector(dockPlayRecent(_:)), keyEquivalent: "")
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
        Task { @MainActor in
            let isCustom = RecentsStore.shared.items.first { $0.url == url }?.hasCustomThumbnail == true
            await AudioPlayer.shared.play(urlString: url, title: title, customArtwork: isCustom)
        }
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
