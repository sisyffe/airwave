import SwiftUI

struct FavoritesList: View {
    @EnvironmentObject var player: AudioPlayer
    @EnvironmentObject var favorites: FavoritesStore
    @State private var renamingID: Favorite.ID?
    @State private var renameText = ""

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
                        isRenaming: renamingID == favorite.id,
                        renameText: $renameText,
                        onPlay: { play(favorite) },
                        onRenameStart: {
                            renameText = favorite.name; renamingID = favorite.id
                        },
                        onRenameCommit: { newName in
                            favorites.rename(favorite, to: newName)
                            renamingID = nil
                        },
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
        Task { await player.play(urlString: favorite.url, title: favorite.name, artwork: favorite.thumbnail) }
    }
}

/// One favorites row: decorative drag handle, thumbnail, name, now-playing
/// badge, "…" menu. Reordering is handled natively by the enclosing List;
/// renaming happens in place, Finder-style.
private struct FavoriteRow: View {
    let favorite: Favorite
    let isCurrent: Bool
    let isRenaming: Bool
    @Binding var renameText: String
    let onPlay: () -> Void
    let onRenameStart: () -> Void
    let onRenameCommit: (String) -> Void
    let onDelete: () -> Void
    @FocusState private var isRenameFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .help("Drag to reorder")
            if isRenaming {
                Thumbnail(data: favorite.thumbnail, size: 24)
                TextField("Name", text: $renameText)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .focused($isRenameFocused)
                    .onSubmit { onRenameCommit(renameText) }
                    .onChange(of: isRenameFocused) { focused in
                        if !focused { onRenameCommit(renameText) }
                    }
                    .task { isRenameFocused = true }
            } else {
                // A Button (rather than a row-wide tap gesture) keeps
                // click-to-play from blocking the List's native reordering.
                Button(action: onPlay) {
                    HStack(spacing: 6) {
                        Thumbnail(data: favorite.thumbnail, size: 24)
                        Text(favorite.name).font(.caption).lineLimit(1)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
            if isCurrent {
                Image(systemName: "speaker.wave.2.fill").font(.caption2).foregroundStyle(.tint)
                    .help("Currently playing")
            }
            Menu {
                FavoriteMenuItems(
                    favorite: favorite,
                    onPlay: onPlay,
                    onRename: onRenameStart,
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
                onRename: onRenameStart,
                onDelete: onDelete)
        }
    }
}

/// Shared favorites menu items, used by both the row's "…" menu and its
/// right-click context menu.
private struct FavoriteMenuItems: View {
    let favorite: Favorite
    let onPlay: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button("Play", action: onPlay)
        Button("Copy Link") { Clipboard.copy(favorite.url) }
        Divider()
        Button("Rename…", action: onRename)
        Button("Delete", role: .destructive, action: onDelete)
    }
}
