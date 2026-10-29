import SwiftUI
import UniformTypeIdentifiers

struct FavoritesList: View {
    @EnvironmentObject var player: AudioPlayer
    @EnvironmentObject var favorites: FavoritesStore
    @State private var dragged: Favorite?
    @State private var dropIndex: Int?
    @State private var renamingID: Favorite.ID?
    @State private var renameText = ""

    var body: some View {
        if favorites.items.isEmpty {
            Text("No favorites yet. Play something, then tap ☆.")
                .foregroundStyle(.secondary).font(.caption)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(favorites.items.enumerated()), id: \.1.id) { pair in
                        let (idx, fav) = pair
                        FavoriteRow(fav: fav,
                                    isCurrent: player.sourceURL == fav.url && player.isPlaying,
                                    isRenaming: renamingID == fav.id,
                                    renameText: $renameText,
                                    showDropDivider: dropIndex == idx,
                                    showDropDividerBelow: dropIndex == favorites.items.count && idx == favorites.items.count - 1,
                                    onPlay: { play(fav) },
                                    onRenameStart: { renameText = fav.name; renamingID = fav.id },
                                    onRenameCommit: { newName in
                                        favorites.rename(fav, to: newName)
                                        renamingID = nil
                                    },
                                    onDragStart: {
                                        dragged = fav
                                        return NSItemProvider(object: fav.id.uuidString as NSString)
                                    },
                                    onDelete: { favorites.remove(fav) })
                            .onDrop(of: [.utf8PlainText],
                                    delegate: FavoritesDropDelegate(item: fav,
                                                                     items: $favorites.items,
                                                                     dragged: $dragged,
                                                                     dropIndex: $dropIndex))
                    }
                }
                // Reserve room for the overlay scrollbar so it never covers the menu.
                .padding(.trailing, 16)
            }
        }
    }

    private func play(_ fav: Favorite) {
        Task { await player.play(urlString: fav.url, title: fav.name, artwork: fav.thumbnail) }
    }
}

/// One favorites row: drag handle, thumbnail, name, now-playing badge, "…" menu.
/// Renaming happens in place, Finder-style.
private struct FavoriteRow: View {
    let fav: Favorite
    let isCurrent: Bool
    let isRenaming: Bool
    @Binding var renameText: String
    let showDropDivider: Bool
    let showDropDividerBelow: Bool
    let onPlay: () -> Void
    let onRenameStart: () -> Void
    let onRenameCommit: (String) -> Void
    let onDragStart: () -> NSItemProvider
    let onDelete: () -> Void
    @FocusState private var renameFocused: Bool

    private var dropDivider: some View {
        Rectangle()
            .fill(Color.accentColor.opacity(0.85))
            .frame(height: 2)
            .frame(maxWidth: .infinity)
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .help("Drag to reorder")
                .onDrag { onDragStart() }
            Thumb(data: fav.thumbnail, size: 24)
            if isRenaming {
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
                Text(fav.name).font(.caption).lineLimit(1)
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
        .contentShape(Rectangle())
        .onTapGesture(perform: onPlay)
        .contextMenu {
            Button("Play", action: onPlay)
            Button("Rename…", action: onRenameStart)
            Divider()
            Button("Delete", role: .destructive, action: onDelete)
        }
        .overlay(alignment: .top) { if showDropDivider { dropDivider } }
        .overlay(alignment: .bottom) { if showDropDividerBelow { dropDivider } }
    }
}

/// Drag-to-reorder for the favorites list: the list stays put while a
/// divider marks where the dragged item would land.
private struct FavoritesDropDelegate: DropDelegate {
    let item: Favorite
    @Binding var items: [Favorite]
    @Binding var dragged: Favorite?
    @Binding var dropIndex: Int?

    private func targetIndex() -> Int? {
        guard let dragged, dragged.id != item.id,
              let from = items.firstIndex(where: { $0.id == dragged.id }),
              let to = items.firstIndex(where: { $0.id == item.id }) else { return nil }
        return from < to ? to + 1 : to
    }

    func dropEntered(info: DropInfo) {
        dropIndex = targetIndex()
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        let accepted = dragged != nil && dropIndex != nil
        if let dragged, let from = items.firstIndex(where: { $0.id == dragged.id }),
           let to = dropIndex {
            var new = items
            new.remove(at: from)
            let insertAt = from < to ? to - 1 : to
            new.insert(dragged, at: min(insertAt, new.count))
            withAnimation(.easeInOut(duration: 0.15)) {
                items = new
            }
        }
        dragged = nil
        dropIndex = nil
        return accepted
    }
}