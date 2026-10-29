import SwiftUI

struct NowPlayingCard: View {
    @EnvironmentObject var player: AudioPlayer
    @EnvironmentObject var favorites: FavoritesStore
    @Binding var showAddFav: Bool
    @State private var showRemoveConfirm = false

    private var isFavorite: Bool { favorites.contains(url: player.sourceURL) }
    private var volumePercentage: Int { Int((player.volume * 100).rounded()) }

    var body: some View {
        VStack(spacing: 6) {
            statusLine.font(.caption2)
            Thumb(data: player.artwork, size: 120)
            Text(player.title.isEmpty ? "Nothing playing" : player.title)
                .font(.callout.weight(.semibold))
                .lineLimit(2).multilineTextAlignment(.center)
            HStack(spacing: 14) {
                Button {
                    if isFavorite { showRemoveConfirm = true }
                    else { showAddFav = true }
                } label: {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .font(.system(size: 14))
                        .foregroundStyle(isFavorite ? Color.accentColor.opacity(0.55) : Color.primary)
                }
                .buttonStyle(.plain)
                .disabled(player.sourceURL.isEmpty)
                .help(isFavorite ? "Remove from favorites" : "Add current to favorites")
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
                Slider(value: $player.volume, in: 0...1)
                    .controlSize(.mini)
                    .accessibilityLabel("Volume")
                    .accessibilityValue("\(volumePercentage) percent")
                    .help("Volume: \(volumePercentage)%")
                Image(systemName: "speaker.wave.3.fill")
                Text("\(volumePercentage)%")
                    .monospacedDigit()
                    .frame(width: 32, alignment: .trailing)
                    .accessibilityLabel("Volume \(volumePercentage) percent")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .confirmationDialog(
            "Remove from favorites?",
            isPresented: $showRemoveConfirm,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let fav = favorites.favorite(for: player.sourceURL) {
                    favorites.remove(fav)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("“\(favorites.favorite(for: player.sourceURL)?.name ?? player.title)” will be removed from your favorites.")
        }
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