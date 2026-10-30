import SwiftUI

/// Detail pane for editing a single favorite in the Favorites settings tab.
struct FavoriteEditor: View {
    @Binding var fav: Favorite
    @EnvironmentObject var player: AudioPlayer

    private var looksPlayable: Bool {
        guard let scheme = URL(string: fav.url)?.scheme else { return false }
        return scheme == "http" || scheme == "https"
    }

    var body: some View {
        Form {
            HStack {
                Spacer()
                Thumb(data: fav.thumbnail, size: 72)
                Spacer()
            }
            TextField("Name", text: $fav.name)
            TextField("Link", text: $fav.url)
                .help("YouTube URL or direct audio/HLS stream link")
            if !fav.url.isEmpty && !looksPlayable {
                Label("This doesn't look like a supported link.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button {
                    Task { await player.play(urlString: fav.url, title: fav.name, artwork: fav.thumbnail) }
                } label: {
                    Label("Play", systemImage: "play.fill")
                }
                .disabled(!looksPlayable)
            }
        }
        .formStyle(.grouped)
    }
}
