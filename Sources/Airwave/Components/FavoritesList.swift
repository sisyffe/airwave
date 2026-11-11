import SwiftUI

struct FavoritesList: View {
    @EnvironmentObject var player: AudioPlayer
    @EnvironmentObject var library: TrackLibrary

    var body: some View {
        if library.favorites.isEmpty {
            Text("No favorites yet. Play something, then tap ☆.")
                .foregroundStyle(.secondary).font(.caption)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(library.favorites) { favorite in
                    FavoriteRow(
                        favorite: favorite,
                        isCurrent: player.track?.id == favorite.id && player.isPlaying,
                        onPlay: { Task { await player.play(favorite) } },
                        onDelete: { library.removeFavorite(favorite.id) })
                }
                .onMove { indices, newOffset in
                    library.moveFavorites(from: indices, to: newOffset)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }
}

/// One favorites row: decorative drag handle, thumbnail, name, now-playing
/// badge, "…" menu. Reordering is handled natively by the enclosing List.
private struct FavoriteRow: View {
    let favorite: Track
    let isCurrent: Bool
    let onPlay: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal")
                .font(.caption2)
                .frame(width: 12)
                .foregroundStyle(.tertiary)
                .help("Drag to reorder")
            // A Button (rather than a row-wide tap gesture) keeps
            // click-to-play from blocking the List's native reordering.
            Button(action: onPlay) {
                HStack(spacing: 6) {
                    Thumbnail(data: ThumbnailStore.data(for: favorite.thumbnailKey), size: 24)
                    Text(favorite.name).font(.caption).lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
            if isCurrent {
                Image(systemName: "speaker.wave.2.fill").font(.caption2).foregroundStyle(.tint)
                    .help("Currently playing")
            }
            Menu {
                FavoriteMenuItems(favorite: favorite, onPlay: onPlay, onDelete: onDelete)
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .controlSize(.small)
            .fixedSize()
            .frame(width: 20, height: 22)
            .help("More options for \(favorite.name)")
        }
        .padding(.vertical, 3)
        .help(favorite.url)
        .contextMenu {
            FavoriteMenuItems(favorite: favorite, onPlay: onPlay, onDelete: onDelete)
        }
    }
}

/// Shared favorites menu items, used by both the row's "…" menu and its
/// right-click context menu.
private struct FavoriteMenuItems: View {
    let favorite: Track
    let onPlay: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button("Play", action: onPlay)
        Button("Copy Link") { Clipboard.copy(favorite.url) }
        Divider()
        Button("Delete", role: .destructive, action: onDelete)
    }
}
