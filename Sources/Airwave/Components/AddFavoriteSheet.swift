import SwiftUI

struct AddFavoriteSheet: View {
    @EnvironmentObject var library: TrackLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    let track: Track
    let thumbnail: Data?

    init(track: Track, thumbnail: Data?) {
        _name = State(initialValue: track.name)
        self.track = track
        self.thumbnail = thumbnail
    }

    private var isNameTaken: Bool { library.isNameTaken(name, excluding: track.id) }

    var body: some View {
        VStack(spacing: 8) {
            Thumbnail(data: thumbnail, size: 64)
            TextField("Name", text: $name).textFieldStyle(.roundedBorder)
            Text(track.url).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            if isNameTaken {
                Label("A favorite already has this name.", systemImage: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    if library.addFavorite(track, name: name) { dismiss() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isNameTaken)
            }
        }
        .padding(12)
        .frame(width: 240)
    }
}
