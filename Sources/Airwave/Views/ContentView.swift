import SwiftUI
import AppKit

struct ContentView: View {
    enum ListMode: Hashable { case favorites, recents }

    @EnvironmentObject var player: AudioPlayer
    @EnvironmentObject var favorites: FavoritesStore
    @State private var link = ""
    @State private var showAddFavorite = false
    @State private var listMode: ListMode = .favorites
    @FocusState private var isLinkFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                NowPlayingCard(showAddFavorite: $showAddFavorite)

                HStack(spacing: 4) {
                    Button(action: playLink) { Image(systemName: "play.fill") }
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(URLValidation.httpURL(from: link) == nil)
                        .help("Play a valid HTTP or HTTPS URL")
                    TextField("YouTube link", text: $link)
                        .controlSize(.small)
                        .help(
                            "Enter a valid HTTP or HTTPS YouTube URL or direct audio/HLS stream URL; other website pages are not supported."
                        )
                        .focused($isLinkFocused)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(playLink)
                    Button(action: paste) {
                        Label("Paste", systemImage: "doc.on.clipboard")
                    }
                    .controlSize(.small)
                    .help("Paste a link from the clipboard")
                }
            }

            .padding(EdgeInsets(top: 0, leading: 10, bottom: 8, trailing: 10))

            Divider()

            Group {
                if listMode == .favorites {
                    FavoritesList()
                } else {
                    RecentsList()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Always-visible bottom bar: the library switcher lives here so it
            // reads as secondary to the player above.
            HStack(spacing: 6) {
                Picker("", selection: $listMode) {
                    Text("Favorites").tag(ListMode.favorites)
                    Text("Recents").tag(ListMode.recents)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.mini)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.bar)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Clear focus on clicks in empty areas from *behind* the content, so the
        // gesture never competes with the favorites list's drag-to-reorder.
        .background(
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { NSApp.keyWindow?.makeFirstResponder(nil) }
        )
        .onExitCommand { NSApp.keyWindow?.makeFirstResponder(nil) }
        .background {
            if #available(macOS 14.0, *) {
                SettingsAccessory()
            } else {
                TitlebarAccessoryInstaller {
                    SettingsWindow.open()
                }
            }
        }
        .onAppear {
            isLinkFocused = true
        }
        .onChange(of: player.sourceURL) { url in
            clearLinkIfPlayedElsewhere(url)
        }
        .sheet(isPresented: $showAddFavorite) {
            AddFavoriteSheet(
                trackID: player.trackID ?? UUID(), initialName: player.title, url: player.sourceURL,
                thumbnailKey: player.artworkKey)
        }
        .onChange(of: player.lastError) { error in
            guard error != nil else { return }
            presentFailure()
        }
    }

    /// A favorite that fails to load gets a modal with actions for it; any other
    /// failure gets a plain notice. Either way the previously playing track keeps playing.
    private func presentFailure() {
        guard let message = player.lastError else { return }
        let failed = player.failedRequest
        guard let favorite = failed.flatMap({ request in favorites.favorite(id: request.trackID) }) else {
            _ = Alerts.choose(title: "Playback failed", message: message, buttons: ["OK"])
            player.clearError()
            return
        }
        let choice = Alerts.choose(
            title: "Couldn't load “\(favorite.name)”",
            message: message,
            buttons: ["Retry", "Edit Link", "Delete", "Cancel"],
            destructive: [2])
        player.clearError()
        switch choice {
        case 0:
            Task { await player.play(PlaybackRequest(favorite: favorite)) }
        case 1:
            SettingsWindow.open()
        case 2:
            favorites.remove(favorite)
        default:
            break
        }
    }

    /// Clears the field when a track starts from a list or the Dock, so the field
    /// does not keep a stale link. Skipped while the user is editing the field, and
    /// when the played link is the one already typed.
    private func clearLinkIfPlayedElsewhere(_ playedURL: String) {
        guard !isLinkFocused, playedURL != link.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
        link = ""
    }

    private func playLink() {
        let url = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard URLValidation.httpURL(from: url) != nil else { return }
        let request = PlaybackRequest.manual(
            url: url, favorites: favorites.items, behavior: Prefs.manualLinkBehavior())
        Task { await player.play(request) }
    }

    private func paste() {
        guard let pasted = Clipboard.string,
            let firstToken = pasted.split(whereSeparator: \.isWhitespace).first
        else { return }
        link = String(firstToken)
        playLink()  // Automatic
    }
}

@available(macOS 14.0, *)
private struct SettingsAccessory: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        TitlebarAccessoryInstaller(openSettings: { openSettings() })
    }
}
