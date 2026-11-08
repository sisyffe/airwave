import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Favorites settings: a reorderable master list with a detail editor, plus
/// metadata-only JSON import/export.
struct FavoritesPreferences: View {
    @EnvironmentObject var library: TrackLibrary
    @State private var selectedFavoriteID: Track.ID?
    @State private var message: String?

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                List(selection: $selectedFavoriteID) {
                    ForEach(library.favorites) { favorite in
                        HStack(spacing: 6) {
                            Image(systemName: "line.3.horizontal")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .help("Drag to reorder")
                            Thumbnail(data: ThumbnailStore.data(for: favorite.thumbnailKey), size: 20)
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
                        library.moveFavorites(from: indices, to: newOffset)
                    }
                }
                .listStyle(.inset)

                Divider()

                HStack(spacing: 4) {
                    Button {
                        add()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("Add a new favorite")
                    Button {
                        delete()
                    } label: {
                        Image(systemName: "minus")
                    }
                    .disabled(selectedFavoriteID == nil)
                    .help("Delete the selected favorite")
                    Spacer()
                    Button("Import…") { importFavorites() }
                        .help("Merge favorites from a JSON file")
                    Button("Export…") { exportFavorites() }
                        .disabled(library.favorites.isEmpty)
                        .help("Save your favorites to a JSON file")
                }
                .controlSize(.small)
                .padding(6)
            }
            .frame(minWidth: 200, idealWidth: 240)

            Group {
                if let id = selectedFavoriteID, library.track(id) != nil {
                    FavoriteEditor(favoriteID: id).id(id)
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
        .onDrop(of: [UTType.fileURL], isTargeted: nil, perform: importDroppedFile)
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
        selectedFavoriteID = library.addDraft()
    }

    private func delete() {
        guard let id = selectedFavoriteID, let index = library.favorites.firstIndex(where: { $0.id == id }) else { return }
        library.removeFavorite(id)
        let remaining = library.favorites
        selectedFavoriteID = remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)].id
    }

    private func exportFavorites() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Airwave Favorites.json"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try FavoritesIO.encode(library.favorites).write(to: url)
            message = "Exported \(library.favorites.filter { !$0.url.isEmpty }.count) favorite(s)."
        } catch {
            message = "Export failed: \(error.localizedDescription)"
        }
    }

    private func importFavorites() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importFavorites(from: url)
    }

    private func importDroppedFile(from providers: [NSItemProvider]) -> Bool {
        guard
            let provider = providers.first(where: {
                $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
            })
        else { return false }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
            guard error == nil, let url = Self.fileURL(from: item) else {
                DispatchQueue.main.async {
                    message = "Import failed: \(error?.localizedDescription ?? "Could not read the dropped file.")"
                }
                return
            }
            DispatchQueue.main.async {
                importFavorites(from: url)
            }
        }
        return true
    }

    private static func fileURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL { return url }
        if let url = item as? NSURL { return url as URL }
        if let data = item as? Data { return URL(dataRepresentation: data, relativeTo: nil) }
        return nil
    }

    private func importFavorites(from url: URL) {
        guard url.pathExtension.lowercased() == "json" else {
            message = "Import failed: Only JSON files can be imported."
            return
        }
        do {
            let incoming = try FavoritesIO.decode(try Data(contentsOf: url))
            let added = library.importFavorites(incoming)
            library.fetchThumbnails(for: added)
            message = added.isEmpty ? "No favorites to import." : "Imported \(added.count) favorite(s)."
        } catch {
            message = "Import failed: \(error.localizedDescription)"
        }
    }
}
