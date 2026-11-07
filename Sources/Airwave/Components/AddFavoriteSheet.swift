import SwiftUI

struct AddFavoriteSheet: View {
    @EnvironmentObject var favorites: FavoritesStore
    @Environment(\.dismiss) private var dismiss
    @State var name: String
    let url: String
    let thumbnail: Data?

    init(initialName: String, url: String, thumbnail: Data?) {
        _name = State(initialValue: initialName)
        self.url = url
        self.thumbnail = thumbnail
    }

    /// The URL is already saved, so `FavoritesStore.add` would silently no-op.
    private var isDuplicate: Bool { favorites.contains(url: url) }

    var body: some View {
        VStack(spacing: 8) {
            Thumbnail(data: thumbnail, size: 64)
            TextField("Name", text: $name).textFieldStyle(.roundedBorder)
            Text(url).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            if isDuplicate {
                Label("Already in Favorites", systemImage: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    favorites.add(name: name, url: url, thumbnail: thumbnail); dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isDuplicate)
            }
        }
        .padding(12)
        .frame(width: 240)
    }
}
