import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Favorites settings: a reorderable master list with a detail editor, plus
/// metadata-only JSON import/export.
struct FavoritesPreferences: View {
    @EnvironmentObject var favorites: FavoritesStore
    @State private var selectedFavoriteID: Favorite.ID?
    @State private var message: String?
    @State private var refreshProgress: (completed: Int, total: Int)?
    @State private var pendingImport: PendingImport?

    /// A decoded import waiting for the user to resolve name conflicts.
    private struct PendingImport {
        let plan: FavoritesIO.ImportPlan
        let existingURLs: Set<String>
    }

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
                    if let progress = refreshProgress {
                        Text("\(progress.completed)/\(progress.total)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Button {
                        refreshThumbnails()
                    } label: {
                        Label("Refresh thumbnails", systemImage: "arrow.triangle.2.circlepath")
                            .labelStyle(.iconOnly)
                    }
                    .disabled(favorites.items.isEmpty || refreshProgress != nil)
                    .help("Re-fetch artwork for all favorites and recents (custom images are kept)")
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
        .onDrop(of: [UTType.fileURL], isTargeted: nil, perform: importDroppedFile)
        .alert("Favorites", isPresented: messageShown) {
            Button("OK") { message = nil }
        } message: {
            Text(message ?? "")
        }
        .confirmationDialog(
            "Name conflicts",
            isPresented: pendingImportShown,
            titleVisibility: .visible
        ) {
            Button("Keep Both") { resolveImport(policy: .suffix) }
            Button("Overwrite") { resolveImport(policy: .overwrite) }
            Button("Ignore Imported") { resolveImport(policy: .skip) }
            Button("Cancel", role: .cancel) { pendingImport = nil }
        } message: {
            Text("\(pendingImport?.plan.conflicts.count ?? 0) imported favorite(s) use a name that already exists.")
        }
    }

    private var messageShown: Binding<Bool> {
        Binding(get: { message != nil }, set: { if !$0 { message = nil } })
    }

    private var pendingImportShown: Binding<Bool> {
        Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } })
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
            let plan = FavoritesIO.plan(incoming, into: favorites.items)
            let existingURLs = Set(favorites.items.map(\.url))
            if plan.hasConflicts {
                pendingImport = PendingImport(plan: plan, existingURLs: existingURLs)
            } else {
                apply(plan, policy: .suffix, existingURLs: existingURLs)
            }
        } catch {
            message = "Import failed: \(error.localizedDescription)"
        }
    }

    /// Applies the import once the user has chosen how to resolve conflicts.
    private func resolveImport(policy: FavoritesIO.ImportPolicy) {
        guard let pending = pendingImport else { return }
        pendingImport = nil
        apply(pending.plan, policy: policy, existingURLs: pending.existingURLs)
    }

    private func apply(
        _ plan: FavoritesIO.ImportPlan, policy: FavoritesIO.ImportPolicy, existingURLs: Set<String>
    ) {
        let result = FavoritesIO.apply(plan, policy: policy, to: favorites.items)
        favorites.items = result.items
        loadThumbnails(for: result.items.filter { !existingURLs.contains($0.url) })
        message = result.added > 0 ? "Imported \(result.added) favorite(s)." : "No new favorites to import."
    }

    private func loadThumbnails(for importedFavorites: [Favorite]) {
        guard !importedFavorites.isEmpty else { return }
        Task { @MainActor in
            await ThumbnailRefresher.refresh(urls: importedFavorites.map(\.url))
        }
    }

    private func refreshThumbnails() {
        refreshProgress = (0, 0)
        Task { @MainActor in
            await ThumbnailRefresher.refreshAll { completed, total in
                refreshProgress = (completed, total)
            }
            refreshProgress = nil
        }
    }
}
