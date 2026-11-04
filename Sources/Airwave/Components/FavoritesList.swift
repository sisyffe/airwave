import SwiftUI

struct FavoritesList: View {
    @EnvironmentObject var player: AudioPlayer
    @EnvironmentObject var favorites: FavoritesStore

    var body: some View {
        if favorites.items.isEmpty {
            Text("No favorites yet. Play something, then tap ☆.")
                .foregroundStyle(.secondary).font(.caption)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(favorites.items) { favorite in
                    FavoriteRow(
                        favorite: favorite,
                        isCurrent: player.sourceURL == favorite.url && player.isPlaying,
                        hasError: player.failedFavoriteID == favorite.id,
                        onPlay: { play(favorite) },
                        onShowInSettings: { SettingsRouter.shared.show(favoriteID: favorite.id) },
                        onDelete: { favorites.remove(favorite) })
                }
                .onMove { indices, newOffset in
                    favorites.items.move(fromOffsets: indices, toOffset: newOffset)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private func play(_ favorite: Favorite) {
        Task {
            await player.play(
                urlString: favorite.url, title: favorite.name, artwork: favorite.thumbnail,
                customArtwork: favorite.hasCustomThumbnail == true, favoriteID: favorite.id)
        }
    }
}

/// One favorites row: decorative drag handle, thumbnail, name, now-playing
/// badge, "…" menu. Reordering is handled natively by the enclosing List.
private struct FavoriteRow: View {
    let favorite: Favorite
    let isCurrent: Bool
    let hasError: Bool
    let onPlay: () -> Void
    let onShowInSettings: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal")
                .font(.caption2)
                .frame(width: 12)
                .foregroundStyle(.tertiary)
                .help("Drag to reorder")
            // A Button (rather than a row-wide tap gesture) keeps click-to-play
            // from blocking the List's native reordering.
            Button(action: onPlay) {
                HStack(spacing: 6) {
                    Thumbnail(data: favorite.thumbnail, size: 24)
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
            if hasError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .help("Couldn't load this favorite")
            }
            Menu {
                FavoriteMenuItems(
                    favorite: favorite,
                    onPlay: onPlay,
                    onShowInSettings: onShowInSettings,
                    onDelete: onDelete)
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
            FavoriteMenuItems(
                favorite: favorite,
                onPlay: onPlay,
                onShowInSettings: onShowInSettings,
                onDelete: onDelete)
        }
    }
}

/// Shared favorites menu items, used by both the row's "…" menu and its
/// right-click context menu.
private struct FavoriteMenuItems: View {
    let favorite: Favorite
    let onPlay: () -> Void
    let onShowInSettings: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button("Play", action: onPlay)
        Button("Copy Link") { Clipboard.copy(favorite.url) }
        Divider()
        Button("Show in Settings", action: onShowInSettings)
        Button("Delete", role: .destructive, action: onDelete)
    }
}
