import SwiftUI
import ServiceManagement

struct PreferencesView: View {
    var body: some View {
        TabView {
            GeneralPrefs().tabItem { Label("General", systemImage: "gearshape") }
            FavoritesPrefs().tabItem { Label("Favorites", systemImage: "star") }
        }
        .frame(width: 460, height: 300)
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

private struct FavoritesPrefs: View {
    @EnvironmentObject var favorites: FavoritesStore
    @State private var selectedID: Favorite.ID?
    @State private var name = ""
    @State private var url = ""

    private var selected: Binding<Favorite>? {
        guard let id = selectedID,
              let index = favorites.items.firstIndex(where: { $0.id == id }) else { return nil }
        let items = $favorites.items
        return Binding<Favorite>(
            get: { items.wrappedValue[index] },
            set: { items.wrappedValue[index] = $0 }
        )
    }

    var body: some View {
        VStack {
            List(selection: $selectedID) {
                ForEach(favorites.items) { fav in
                    HStack(spacing: 6) {
                        Thumb(data: fav.thumbnail, size: 20)
                        Text(fav.name).lineLimit(1)
                    }
                    .tag(fav.id)
                }
                .onMove { favorites.items.move(fromOffsets: $0, toOffset: $1) }
            }
            .listStyle(.plain)
            .frame(height: 120)
            Form {
                if let sel = selected {
                    TextField("Name", text: sel.name)
                    TextField("Link", text: sel.url)
                        .help("YouTube URL or direct audio/HLS stream link")
                } else {
                    TextField("Name", text: .constant(""), prompt: Text("Select a favorite above"))
                        .disabled(true)
                    TextField("Link", text: .constant(""), prompt: Text("Select a favorite above"))
                        .disabled(true)
                }
            }
            .formStyle(.grouped)
            .padding(-8)
            Divider()
            HStack {
                TextField("Name", text: $name)
                TextField("Link", text: $url)
                    .help("YouTube URL or direct audio/HLS stream link")
                Button("Add") { favorites.add(name: name, url: url); name = ""; url = "" }
                    .disabled(url.isEmpty)
                    .help("Add this link to favorites")
            }
        }
        .padding()
    }
}
