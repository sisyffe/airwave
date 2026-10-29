import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var player: AudioPlayer
    @EnvironmentObject var favorites: FavoritesStore
    @State private var link = ""
    @State private var showAddFav = false
    @FocusState private var linkFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                NowPlayingCard(showAddFav: $showAddFav)

                HStack(spacing: 4) {
                    Button(action: playLink) { Image(systemName: "play.fill") }
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(link.trimmingCharacters(in: .whitespaces).isEmpty)
                        .help("Play link")
                    TextField("YouTube link", text: $link)
                        .controlSize(.small)
                        .help("Uses YouTubeKit. Paste a YouTube URL or a direct audio/HLS stream link; other website pages are not supported.")
                        .focused($linkFocused)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(playLink)
                    Button(action: paste) {
                        Label("Paste", systemImage: "doc.on.clipboard")
                    }
                        .controlSize(.small)
                        .help("Paste a link from the clipboard")
                }

                HStack {
                    Text("Favorites").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                }

                FavoritesList()
            }
            .padding(EdgeInsets(top: 0, leading: 10, bottom: 10, trailing: 10))
        }
        .contentShape(Rectangle())
        .onTapGesture { NSApp.keyWindow?.makeFirstResponder(nil) }
        .onExitCommand { NSApp.keyWindow?.makeFirstResponder(nil) }
        .background(TitlebarAccessoryInstaller())
        .onAppear {
            linkFocused = true
        }
        .sheet(isPresented: $showAddFav) {
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
        let url = link.trimmingCharacters(in: .whitespaces)
        guard !url.isEmpty else { return }
        let fav = favorites.favorite(for: url)
        Task { await player.play(urlString: url, title: fav?.name, artwork: fav?.thumbnail) }
    }

    private func paste() {
        guard let s = NSPasteboard.general.string(forType: .string),
              let first = s.split(whereSeparator: \.isWhitespace).first else { return }
        link = String(first)
    }
}