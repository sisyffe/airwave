import SwiftUI

struct NowPlayingCard: View {
    @EnvironmentObject var player: AudioPlayer
    @EnvironmentObject var favorites: FavoritesStore
    @Binding var showAddFavorite: Bool
    @State private var showRemoveConfirm = false
    @State private var isAdjustingVolume = false
    @State private var showOptions = false

    private var isFavorite: Bool { favorites.contains(url: player.sourceURL) }
    private var volumePercentage: Int { Int((player.volume * 100).rounded()) }

    /// Square box shared by the favorite star and the options arrow so the two
    /// corner buttons read as symmetrical (glyphs stay at their own sizes).
    private static let controlButtonSize: CGFloat = 16
    private static let maximumVolume: Float = 1.0
    private static let volumeSnap: Float = maximumVolume / 50
    private static let volumeStep: Float = maximumVolume / 4
    /// Volume stops are generated from the slider range; the slider snaps to a stop when it gets close.
    private static var volumeStops: [Float] {
        let stops = stride(from: 0, through: maximumVolume, by: volumeStep).map { $0 }
        return stops.last == maximumVolume ? stops : stops + [maximumVolume]
    }

    private var volumeBinding: Binding<Float> {
        Binding(
            get: { player.volume },
            set: { newVolume in
                let clamped = min(max(newVolume, 0), Self.maximumVolume)
                if let stop = Self.volumeStops.first(where: { abs($0 - clamped) <= Self.volumeSnap }) {
                    player.volume = stop
                } else {
                    player.volume = clamped
                }
            }
        )
    }

    var body: some View {
        VStack(spacing: 6) {
            statusLine.font(.caption2)
            Thumbnail(data: player.artwork, size: 120)
            Text(player.title.isEmpty ? "Nothing playing" : player.title)
                .font(.callout.weight(.semibold))
                .lineLimit(2).multilineTextAlignment(.center)
            if let song = player.streamTitle, song != player.title {
                Text("♪ \(song)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity)
            }
            HStack(alignment: .center, spacing: 14) {
                Button {
                    player.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 18))
                        .offset(y: -2)
                }
                .buttonStyle(.plain)
                .disabled(player.sourceURL.isEmpty)
                .help("Reload stream")
                Button {
                    player.toggle()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 26))
                }
                .buttonStyle(.plain)
                .disabled(player.sourceURL.isEmpty)
                .help(player.isPlaying ? "Pause" : "Play")
                Button {
                    player.stop()
                } label: {
                    Image(systemName: "stop.circle")
                        .font(.system(size: 18))
                }
                .buttonStyle(.plain)
                .disabled(player.state == .idle)
                .help("Stop")
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: "speaker.fill").frame(width: 16)
                Slider(value: volumeBinding, in: 0...Self.maximumVolume) { isEditing in
                    isAdjustingVolume = isEditing
                }
                .controlSize(.mini)
                .accessibilityLabel("Volume")
                .accessibilityValue("\(volumePercentage) percent")
                .help("Volume: \(volumePercentage)%")
                .overlay {
                    GeometryReader { geometry in
                        let thumbRadius = geometry.size.height / 2
                        if isAdjustingVolume {
                            Text("\(volumePercentage)%")
                                .font(.caption2.monospacedDigit())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(.regularMaterial, in: Capsule())
                                .position(
                                    x: thumbRadius
                                        + CGFloat(player.volume / Self.maximumVolume)
                                        * (geometry.size.width - 2 * thumbRadius),
                                    y: -16
                                )
                                .accessibilityHidden(true)
                        }
                    }
                }
                Image(systemName: "speaker.wave.3.fill").frame(width: 16)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .topLeading) { favoriteButton.padding(6) }
        .overlay(alignment: .topTrailing) { optionsButton.padding(6) }
        .confirmationDialog(
            "Remove from favorites?",
            isPresented: $showRemoveConfirm,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let favorite = favorites.favorite(for: player.sourceURL) {
                    favorites.remove(favorite)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("“\(favorites.favorite(for: player.sourceURL)?.name ?? player.title)” will be removed from your favorites.")
        }
    }

    private var favoriteButton: some View {
        Button {
            if isFavorite { showRemoveConfirm = true } else { showAddFavorite = true }
        } label: {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .font(.system(size: 14))
                .foregroundStyle(isFavorite ? Color.accentColor.opacity(0.55) : Color.primary)
                .frame(width: Self.controlButtonSize, height: Self.controlButtonSize)
        }
        .buttonStyle(.plain)
        .disabled(player.sourceURL.isEmpty)
        .help(isFavorite ? "Remove from favorites" : "Add current to favorites")
    }

    private var optionsButton: some View {
        Button {
            showOptions.toggle()
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(showOptions ? 0 : 180))
                .frame(width: Self.controlButtonSize, height: Self.controlButtonSize)
        }
        .buttonStyle(.plain)
        .help("More controls")
        .popover(isPresented: $showOptions, arrowEdge: .bottom) {
            PlaybackOptionsPopover()
        }
    }

    @ViewBuilder private var statusLine: some View {
        switch player.state {
        case .idle: Text("Idle").foregroundStyle(.secondary)
        case .loading:
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini); Text("Loading…")
            }.foregroundStyle(.secondary)
        case .playing:
            if player.isLive {
                Label("Live", systemImage: "dot.radiowaves.left.and.right").foregroundStyle(.green)
            } else {
                Label("Playing", systemImage: "play.fill").foregroundStyle(.green)
            }
        case .paused: Text("Paused").foregroundStyle(.secondary)
        }
    }
}
