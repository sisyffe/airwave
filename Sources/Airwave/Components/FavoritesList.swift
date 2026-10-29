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
                ForEach(favorites.items) { fav in
                    FavoriteRow(fav: fav,
                                isCurrent: player.sourceURL == fav.url && player.isPlaying,
                                isRenaming: renamingID == fav.id,
                                renameText: $renameText,
                                onPlay: { play(fav) },
                                onRenameStart: { renameText = fav.name; renamingID = fav.id },
                                onRenameCommit: { newName in
                                    favorites.rename(fav, to: newName)
                                    renamingID = nil
                                },
                                onDelete: { favorites.remove(fav) })
                }
                .onMove { indices, newOffset in
                    favorites.items.move(fromOffsets: indices, toOffset: newOffset)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private func play(_ fav: Favorite) {
        Task { await player.play(urlString: fav.url, title: fav.name, artwork: fav.thumbnail) }
    }
}

/// One favorites row: decorative drag handle, thumbnail, name, now-playing
/// badge, "…" menu. Reordering is handled natively by the enclosing List;
/// renaming happens in place, Finder-style.
private struct FavoriteRow: View {
    let fav: Favorite
    let isCurrent: Bool
    let isRenaming: Bool
    @Binding var renameText: String
    let onPlay: () -> Void
    let onRenameStart: () -> Void
    let onRenameCommit: (String) -> Void
    let onDelete: () -> Void
    @FocusState private var renameFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .help("Drag to reorder")
            if isRenaming {
                Thumb(data: fav.thumbnail, size: 24)
                TextField("Name", text: $renameText)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .focused($renameFocused)
                    .onSubmit { onRenameCommit(renameText) }
                    .onChange(of: renameFocused) { _, focused in
                        if !focused { onRenameCommit(renameText) }
                    }
                    .task { renameFocused = true }
            } else {
                // A Button (rather than a row-wide tap gesture) keeps
                // click-to-play from blocking the List's native reordering.
                Button(action: onPlay) {
                    HStack(spacing: 6) {
                        Thumb(data: fav.thumbnail, size: 24)
                        Text(fav.name).font(.caption).lineLimit(1)
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
                Button("Play", action: onPlay)
                Button("Rename…", action: onRenameStart)
                Divider()
                Button("Delete", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .controlSize(.small)
            .fixedSize()
            .frame(width: 20, height: 22)
            .help("More options for \(fav.name)")
        }
        .padding(.vertical, 3)
        .help(fav.url)
        .contextMenu {
            Button("Play", action: onPlay)
            Button("Rename…", action: onRenameStart)
            Divider()
            Button("Delete", role: .destructive, action: onDelete)
        }
    }
}
