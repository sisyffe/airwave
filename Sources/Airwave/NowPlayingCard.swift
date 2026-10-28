import SwiftUI

struct NowPlayingCard: View {
    @EnvironmentObject var player: AudioPlayer
    @EnvironmentObject var favorites: FavoritesStore
    @Binding var showAddFav: Bool

    var body: some View {
        VStack(spacing: 6) {
            statusLine.font(.caption2)
            Thumb(data: player.artwork, size: 120)
            Text(player.title.isEmpty ? "Nothing playing" : player.title)
                .font(.callout.weight(.semibold))
                .lineLimit(2).multilineTextAlignment(.center)
            HStack(spacing: 14) {
                Button { showAddFav = true } label: {
                    Image(systemName: "star").font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .disabled(player.sourceURL.isEmpty || favorites.contains(url: player.sourceURL))
                .help("Add current to favorites")
                Button { player.toggle() } label: {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 26))
                }
                .buttonStyle(.plain)
                .disabled(player.sourceURL.isEmpty)
                .help(player.isPlaying ? "Pause" : "Play")
                Button { player.stop() } label: {
                    Image(systemName: "stop.circle").font(.system(size: 18))
                }
                .buttonStyle(.plain)
                .disabled(player.state == .idle)
                .help("Stop")
            }
            HStack(spacing: 4) {
                Image(systemName: "speaker.fill")
                Slider(value: $player.volume, in: 0...1).controlSize(.mini)
                Image(systemName: "speaker.wave.3.fill")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder private var statusLine: some View {
        switch player.state {
        case .idle: Text("Idle").foregroundStyle(.secondary)
        case .loading: HStack(spacing: 4) { ProgressView().controlSize(.mini); Text("Loading…") }.foregroundStyle(.secondary)
        case .playing: Label("Live", systemImage: "dot.radiowaves.left.and.right").foregroundStyle(.green)
        case .paused: Text("Paused").foregroundStyle(.secondary)
        }
    }
}