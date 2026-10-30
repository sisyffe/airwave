import SwiftUI

/// Detail pane for editing a single favorite in the Favorites settings tab.
struct FavoriteEditor: View {
    @Binding var favorite: Favorite
    @EnvironmentObject var player: AudioPlayer

    private var looksPlayable: Bool {
        guard let scheme = URL(string: favorite.url)?.scheme else { return false }
        return scheme == "http" || scheme == "https"
    }

    var body: some View {
        Form {
            HStack {
                Spacer()
                Thumbnail(data: favorite.thumbnail, size: 72)
                Spacer()
            }
            TextField("Name", text: $favorite.name)
            TextField("Link", text: $favorite.url)
                .help("YouTube URL or direct audio/HLS stream link")
            if !favorite.url.isEmpty && !looksPlayable {
                Label("This doesn't look like a supported link.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button {
                    Task { await player.play(urlString: favorite.url, title: favorite.name, artwork: favorite.thumbnail) }
                } label: {
                    Label("Play", systemImage: "play.fill")
                }
                .disabled(!looksPlayable)
            }
        }
        .formStyle(.grouped)
    }
}
