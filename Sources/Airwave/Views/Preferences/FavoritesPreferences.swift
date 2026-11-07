import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Favorites settings: a reorderable master list with a detail editor, plus
/// metadata-only JSON import/export.
struct FavoritesPreferences: View {
    @EnvironmentObject var favorites: FavoritesStore
    @ObservedObject private var router = SettingsRouter.shared
    @State private var selectedFavoriteID: Favorite.ID?
    @State private var message: String?

    private var selectedBinding: Binding<Favorite>? {
        guard let id = selectedFavoriteID,
            let index = favorites.items.firstIndex(where: { $0.id == id })
        else { return nil }
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
                            Thumbnail(key: favorite.thumbnailKey, size: 20)
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

                HStack(alignment: .center, spacing: 8) {
                    VStack(spacing: 4) {
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
                    }
                    Spacer()
                    Button("Refresh Thumbnails") { refreshAllThumbnails() }
                        .disabled(favorites.items.isEmpty)
                        .help("Fetch the latest artwork for every favorite. Custom thumbnails are kept.")
                    Spacer()
                    VStack(spacing: 4) {
                        Button("Import…") { importFavorites() }
                            .help("Merge favorites from a JSON file")
                        Button("Export…") { exportFavorites() }
                            .disabled(favorites.items.isEmpty)
                            .help("Save your favorites to a JSON file")
                    }
                    .frame(width: 96)
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
        .onAppear { applyRouterSelection() }
        .onChange(of: router.selectedFavoriteID) { _ in applyRouterSelection() }
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

    /// Selects the favorite the router asked for ("Show in Settings"), then clears the request.
    private func applyRouterSelection() {
        guard let id = router.selectedFavoriteID else { return }
        selectedFavoriteID = id
        router.selectedFavoriteID = nil
    }

    private func add() {
        let favorite = Favorite(name: "New Favorite", url: "")
        favorites.items.append(favorite)
        selectedFavoriteID = favorite.id
    }

    private func delete() {
        guard let id = selectedFavoriteID, let index = favorites.items.firstIndex(where: { $0.id == id }) else { return }
        favorites.items.remove(at: index)
        selectedFavoriteID =
            favorites.items.isEmpty
            ? nil
            : favorites.items[min(index, favorites.items.count - 1)].id
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
            // Conflicts are settled before anything is written, so Cancel leaves the list untouched.
            let plan = FavoritesIO.plan(incoming, against: favorites.items)
            let strategy: FavoritesIO.ConflictStrategy
            if plan.conflicts.isEmpty {
                strategy = .createDuplicates
            } else {
                guard let chosen = Self.conflictStrategy(for: plan.conflicts.count) else { return }
                strategy = chosen
            }
            let before = Set(favorites.items.map(\.id))
            favorites.items = FavoritesIO.apply(plan, to: favorites.items, strategy: strategy)
            let added = favorites.items.filter { !before.contains($0.id) }
            refreshThumbnails(for: added)
            message =
                added.isEmpty
                ? "No new favorites to import." : "Imported \(added.count) favorite(s)."
        } catch {
            message = "Import failed: \(error.localizedDescription)"
        }
    }

    /// Asks how to resolve name conflicts. Nil when the user cancels.
    private static func conflictStrategy(for count: Int) -> FavoritesIO.ConflictStrategy? {
        let choice = Alerts.choose(
            title: "Some favorites already exist",
            message:
                "\(count) favorite(s) in the file have the same name as one in your list. Create duplicates adds numbered copies, Overwrite replaces the existing favorite, and Ignore skips the conflicting ones.",
            buttons: ["Create Duplicates", "Overwrite", "Ignore", "Cancel"],
            destructive: [1])
        switch choice {
        case 0: return .createDuplicates
        case 1: return .overwrite
        case 2: return .ignore
        default: return nil
        }
    }

    private func refreshAllThumbnails() {
        refreshThumbnails(for: favorites.items)
    }

    /// Fetches artwork for each distinct URL in `targets` (in parallel) and stores it on
    /// the favorites that use it. Favorites with a custom thumbnail are skipped by the store.
    private func refreshThumbnails(for targets: [Favorite]) {
        let urls = Set(targets.map(\.url))
        guard !urls.isEmpty else { return }

        Task { @MainActor in
            await withTaskGroup(of: (String, Data?).self) { group in
                for url in urls {
                    group.addTask {
                        (url, await StreamResolver.thumbnail(for: url))
                    }
                }

                for await (url, thumbnail) in group {
                    if let thumbnail, let key = ThumbnailCache.store(thumbnail) {
                        favorites.setThumbnailKey(key, for: url)
                    }
                }
            }
        }
    }
}
