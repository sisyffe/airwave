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
                ForEach(recents.items) { track in
                    RecentRow(
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
        Task { await player.play(urlString: track.url, title: track.name, artwork: track.thumbnail) }
    }
}

private struct RecentRow: View {
    let track: RecentTrack
    let isCurrent: Bool
    let onPlay: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Thumbnail(data: track.thumbnail, size: 24)
            Text(track.name).font(.caption).lineLimit(1)
            Spacer(minLength: 0)
            if isCurrent {
                Image(systemName: "speaker.wave.2.fill").font(.caption2).foregroundStyle(.tint)
                    .help("Currently playing")
            }
            Menu {
                Button("Play", action: onPlay)
                Divider()
                Button("Remove from Recents", role: .destructive, action: onRemove)
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
            Button("Play", action: onPlay)
            Divider()
            Button("Remove from Recents", role: .destructive, action: onRemove)
        }
    }
}
