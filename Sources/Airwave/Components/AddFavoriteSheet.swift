import SwiftUI

struct AddFavoriteSheet: View {
    @EnvironmentObject var favorites: FavoritesStore
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var player: AudioPlayer
    @State var name: String
    /// Identity the saved favorite takes, so it matches the playing track and its recent entry.
    let trackID: UUID
    let url: String
    let thumbnailKey: String?

    init(trackID: UUID, initialName: String, url: String, thumbnailKey: String?) {
        self.trackID = trackID
        _name = State(initialValue: initialName)
        self.url = url
        self.thumbnailKey = thumbnailKey
    }

    private var isNameTaken: Bool { !favorites.isNameAvailable(name) }

    var body: some View {
        VStack(spacing: 8) {
            Thumbnail(key: thumbnailKey, size: 64)
            TextField("Name", text: $name).textFieldStyle(.roundedBorder)
            Text(url).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            if isNameTaken {
                Label("A favorite with this name already exists", systemImage: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    if favorites.add(name: name, url: url, thumbnailKey: thumbnailKey, id: trackID),
                        let saved = favorites.favorite(id: trackID)
                    {
                        player.adoptFavorite(saved)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isNameTaken)
            }
        }
        .padding(12)
        .frame(width: 240)
    }
}
