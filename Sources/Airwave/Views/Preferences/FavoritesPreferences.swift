import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Favorites settings: a reorderable master list with a detail editor, plus
/// lossless JSON import/export.
struct FavoritesPreferences: View {
    @EnvironmentObject var favorites: FavoritesStore
    @State private var selectedFavoriteID: Favorite.ID?
    @State private var message: String?

    private var selectedBinding: Binding<Favorite>? {
        guard let id = selectedFavoriteID,
              let index = favorites.items.firstIndex(where: { $0.id == id }) else { return nil }
        let items = $favorites.items
        return Binding<Favorite>(
            get: { items.wrappedValue[index] },
            set: { items.wrappedValue[index] = $0 }
        )
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                List(selection: $selectedFavoriteID) {
                    ForEach(favorites.items) { favorite in
                        HStack(spacing: 6) {
                            Image(systemName: "line.3.horizontal")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .help("Drag to reorder")
                            Thumbnail(data: favorite.thumbnail, size: 20)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(favorite.name).lineLimit(1)
                                if let host = URL(string: favorite.url)?.host {
                                    Text(host).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                        }
                        .tag(favorite.id)
                    }
                    .onMove { indices, newOffset in
                        favorites.items.move(fromOffsets: indices, toOffset: newOffset)
                    }
                }
                .listStyle(.inset)

                Divider()

                HStack(spacing: 4) {
                    Button { add() } label: { Image(systemName: "plus") }
                        .help("Add a new favorite")
                    Button { delete() } label: { Image(systemName: "minus") }
                        .disabled(selectedFavoriteID == nil)
                        .help("Delete the selected favorite")
                    Spacer()
                    Button("Import…") { importFavorites() }
                        .help("Merge favorites from a JSON file")
                    Button("Export…") { exportFavorites() }
                        .disabled(favorites.items.isEmpty)
                        .help("Save your favorites to a JSON file")
                }
                .controlSize(.small)
                .padding(6)
            }
            .frame(minWidth: 200, idealWidth: 240)

            Group {
                if let binding = selectedBinding {
                    FavoriteEditor(favorite: binding)
                } else {
                    Text("Select a favorite to edit, or add a new one.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                }
            }
            .frame(minWidth: 240)
        }
        .alert("Favorites", isPresented: messageShown) {
            Button("OK") { message = nil }
        } message: {
            Text(message ?? "")
        }
    }

    private var messageShown: Binding<Bool> {
        Binding(get: { message != nil }, set: { if !$0 { message = nil } })
    }

    private func add() {
        let favorite = Favorite(name: "New Favorite", url: "")
        favorites.items.append(favorite)
        selectedFavoriteID = favorite.id
    }

    private func delete() {
        guard let id = selectedFavoriteID, let index = favorites.items.firstIndex(where: { $0.id == id }) else { return }
        favorites.items.remove(at: index)
        selectedFavoriteID = nil
    }

    private func exportFavorites() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Airwave Favorites.json"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try FavoritesIO.encode(favorites.items).write(to: url)
            message = "Exported \(favorites.items.count) favorite(s)."
        } catch {
            message = "Export failed: \(error.localizedDescription)"
        }
    }

    private func importFavorites() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let incoming = try FavoritesIO.decode(try Data(contentsOf: url))
            let result = FavoritesIO.merge(incoming, into: favorites.items)
            favorites.items = result.items
            message = result.added > 0 ? "Imported \(result.added) favorite(s)." : "No new favorites to import."
        } catch {
            message = "Import failed: \(error.localizedDescription)"
        }
    }
}
