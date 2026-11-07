import AppKit

/// Actions shared by the app's menu, keyboard shortcuts and buttons, so a
/// shortcut and its button always do the same thing.
@MainActor
enum PlaybackActions {
    /// Volume change per ⌘↑ / ⌘↓ press.
    static let volumeStep: Float = 0.1

    /// Copies the playing link, if any.
    static func copyPlayingLink() {
        let url = AudioPlayer.shared.sourceURL
        guard !url.isEmpty else { return }
        Clipboard.copy(url)
    }

    /// Toggles the playing track in or out of favorites.
    static func toggleFavorite() {
        NotificationCenter.default.post(name: .airwaveToggleFavorite, object: nil)
    }

    static func changeVolume(by delta: Float) {
        let player = AudioPlayer.shared
        player.volume = min(max(player.volume + delta, 0), 1)
    }
}

extension Notification.Name {
    /// Posted by ⌘F. The Now Playing card owns the add and remove dialogs.
    static let airwaveToggleFavorite = Notification.Name("airwaveToggleFavorite")
    /// Posted by ⌘V outside a text field. The main window pastes the link and plays it.
    static let airwavePasteLink = Notification.Name("airwavePasteLink")
}
