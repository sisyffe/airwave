import SwiftUI
import AppKit
import ServiceManagement
import UniformTypeIdentifiers

struct PreferencesView: View {
    var body: some View {
        TabView {
            GeneralPrefs().tabItem { Label("General", systemImage: "gearshape") }
            RecentsPrefs().tabItem { Label("Recents", systemImage: "clock.arrow.circlepath") }
            FavoritesPrefs().tabItem { Label("Favorites", systemImage: "star") }
        }
        .frame(width: 560, height: 380)
    }
}

private struct GeneralPrefs: View {
    @AppStorage(Prefs.hotstart) private var hotstart = true
    @AppStorage(Prefs.quitOnLastWindowClosed) private var quitOnLastWindowClosed = Prefs.defaultQuitOnLastWindowClosed
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Toggle("Hotstart: play automatically when Airwave opens", isOn: $hotstart)
                .help("Resumes the last played source")
            Toggle("Quit when the last window closes", isOn: $quitOnLastWindowClosed)
                .help("On: closing the last window quits Airwave. Off: Airwave stays running and audio continues, like a standard macOS app. Use ⌘Q to quit.")
            Toggle("Open Airwave at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, on in
                    do { on ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() }
                    catch { launchAtLogin = !on }
                }
                .help("Requires running Airwave as a bundled .app")
        }
        .formStyle(.grouped)
    }
}

private struct RecentsPrefs: View {
    @EnvironmentObject var recents: RecentsStore
    @State private var confirmClear = false

    private var maxCountBinding: Binding<Double> {
        Binding(get: { Double(recents.maxCount) },
                set: { recents.maxCount = Int($0.rounded()) })
    }

    var body: some View {
        Form {
            LabeledContent("History size") {
                HStack(spacing: 8) {
                    Slider(value: maxCountBinding,
                           in: Double(Prefs.minRecentMaxCount)...Double(Prefs.maxRecentMaxCount),
                           step: 1)
                        .frame(width: 160)
                    Text("\(recents.maxCount)")
                        .monospacedDigit()
                        .frame(width: 22, alignment: .trailing)
                }
            }
            .help("How many recently played tracks to remember for quick play.")

            LabeledContent("Clear history") {
                Button("Clear Recent Tracks", role: .destructive) { confirmClear = true }
                    .disabled(recents.items.isEmpty)
                    .help("Remove all recently played tracks.")
            }
            .help("Removes every entry from the Recents list.")
        }
        .formStyle(.grouped)
        .confirmationDialog("Clear recent history?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear", role: .destructive) { recents.clear() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes all \(recents.items.count) recently played track(s).")
        }
    }
}

private struct FavoritesPrefs: View {
    @EnvironmentObject var favorites: FavoritesStore
    @State private var selectedID: Favorite.ID?
    @State private var message: String?

    private var selectedBinding: Binding<Favorite>? {
        guard let id = selectedID,
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
                List(selection: $selectedID) {
                    ForEach(favorites.items) { fav in
                        HStack(spacing: 6) {
                            Image(systemName: "line.3.horizontal")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .help("Drag to reorder")
                            Thumb(data: fav.thumbnail, size: 20)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(fav.name).lineLimit(1)
                                if let host = URL(string: fav.url)?.host {
                                    Text(host).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                        }
                        .tag(fav.id)
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
                        .disabled(selectedID == nil)
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
                    FavoriteEditor(fav: binding)
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
        let fav = Favorite(name: "New Favorite", url: "")
        favorites.items.append(fav)
        selectedID = fav.id
    }

    private func delete() {
        guard let id = selectedID, let index = favorites.items.firstIndex(where: { $0.id == id }) else { return }
        favorites.items.remove(at: index)
        selectedID = nil
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

private struct FavoriteEditor: View {
    @Binding var fav: Favorite
    @EnvironmentObject var player: AudioPlayer

    private var looksPlayable: Bool {
        guard let scheme = URL(string: fav.url)?.scheme else { return false }
        return scheme == "http" || scheme == "https"
    }

    var body: some View {
        Form {
            HStack {
                Spacer()
                Thumb(data: fav.thumbnail, size: 72)
                Spacer()
            }
            TextField("Name", text: $fav.name)
            TextField("Link", text: $fav.url)
                .help("YouTube URL or direct audio/HLS stream link")
            if !fav.url.isEmpty && !looksPlayable {
                Label("This doesn't look like a supported link.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button {
                    Task { await player.play(urlString: fav.url, title: fav.name, artwork: fav.thumbnail) }
                } label: {
                    Label("Play", systemImage: "play.fill")
                }
                .disabled(!looksPlayable)
            }
        }
        .formStyle(.grouped)
    }
}
