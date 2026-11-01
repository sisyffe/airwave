import SwiftUI

struct RecentsList: View {
    @EnvironmentObject var player: AudioPlayer
    @EnvironmentObject var recents: RecentsStore

    var body: some View {
        if recents.items.isEmpty {
            Text("No recent tracks yet. Play something to build your history.")
                .foregroundStyle(.secondary).font(.caption)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(Array(recents.items.enumerated()), id: \.element.id) { index, track in
                    RecentRow(
                        rank: index + 1,
                        track: track,
                        isCurrent: player.sourceURL == track.url && player.isPlaying,
                        onPlay: { play(track) },
                        onRemove: { recents.remove(track) })
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private func play(_ track: RecentTrack) {
        Task {
            await player.play(
                urlString: track.url, title: track.name, artwork: track.thumbnail,
                customArtwork: track.hasCustomThumbnail == true)
        }
    }
}

private struct RecentRow: View {
    let rank: Int
    let track: RecentTrack
    let isCurrent: Bool
    let onPlay: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text("\(rank).")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .frame(width: 12)
            Thumbnail(data: track.thumbnail, size: 24)
            // Align the row separator with the track name (as in the favorites
            // list) instead of the leading rank number.
            Text(track.name)
                .font(.caption)
                .lineLimit(1)
                .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
            Spacer(minLength: 0)
            if isCurrent {
                Image(systemName: "speaker.wave.2.fill").font(.caption2).foregroundStyle(.tint)
                    .help("Currently playing")
            }
            Menu {
                RecentMenuItems(track: track, onPlay: onPlay, onRemove: onRemove)
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .controlSize(.small)
            .fixedSize()
            .frame(width: 20, height: 22)
            .help("More options for \(track.name)")
        }
        .padding(.vertical, 3)
        .help(track.url)
        .contentShape(Rectangle())
        .onTapGesture(perform: onPlay)
        .contextMenu {
            RecentMenuItems(track: track, onPlay: onPlay, onRemove: onRemove)
        }
    }
}

/// Shared recents menu items, used by both the row's "…" menu and its
/// right-click context menu.
private struct RecentMenuItems: View {
    let track: RecentTrack
    let onPlay: () -> Void
    let onRemove: () -> Void

    var body: some View {
        Button("Play", action: onPlay)
        Button("Copy Link") { Clipboard.copy(track.url) }
        Divider()
        Button("Remove from Recents", role: .destructive, action: onRemove)
    }
}
