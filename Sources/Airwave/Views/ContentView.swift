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
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
            }
        }
        .onAppear {
            isLinkFocused = true
        }
        .sheet(isPresented: $showAddFavorite) {
            AddFavoriteSheet(initialName: player.title, url: player.sourceURL, thumbnail: player.artwork)
        }
        .alert("Playback failed", isPresented: errorShown) {
            Button("OK") { player.clearError() }
        } message: {
            Text(player.lastError ?? "")
        }
    }

    private var errorShown: Binding<Bool> {
        Binding(get: { player.lastError != nil }, set: { if !$0 { player.clearError() } })
    }

    private func playLink() {
        let url = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard URLValidation.httpURL(from: url) != nil else { return }
        let favorite = favorites.favorite(for: url)
        Task { await player.play(urlString: url, title: favorite?.name, artwork: favorite?.thumbnail) }
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
