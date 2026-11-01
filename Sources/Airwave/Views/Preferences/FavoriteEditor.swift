import SwiftUI
import UniformTypeIdentifiers

/// Detail pane for editing a single favorite in the Favorites settings tab.
struct FavoriteEditor: View {
    @Binding var favorite: Favorite
    @EnvironmentObject var player: AudioPlayer
    @EnvironmentObject var favorites: FavoritesStore
    @EnvironmentObject var recents: RecentsStore

    @State private var showImporter = false
    @State private var message: String?
    @State private var isDropTargeted = false

    private static let thumbnailSize: CGFloat = 72
    /// Matches `Thumbnail`'s corner radius so the drop highlight aligns.
    private static let cornerRadiusScale: CGFloat = 0.12

    private var looksPlayable: Bool {
        URLValidation.httpURL(from: favorite.url) != nil
    }

    var body: some View {
        Form {
            thumbnailSection
            TextField("Name", text: $favorite.name)
            TextField("Link", text: $favorite.url)
                .help("YouTube URL or direct audio/HLS stream URL")
            if !favorite.url.isEmpty && !looksPlayable {
                Label("This doesn't look like a supported link.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button {
                    Task {
                        await player.play(
                            urlString: favorite.url, title: favorite.name, artwork: favorite.thumbnail,
                            customArtwork: favorite.hasCustomThumbnail == true)
                    }
                } label: {
                    Label("Play", systemImage: "play.fill")
                }
                .disabled(!looksPlayable)
            }
            // Trim only applies to finite tracks, so it appears once playback has
            // confirmed the track has an end.
            if favorite.isFinite == true {
                Section {
                    timeRow(title: "Start offset", time: $favorite.startOffset)
                    timeRow(title: "End offset", time: $favorite.endOffset)
                } header: {
                    Text("Trim")
                } footer: {
                    Text("Applies on reload. End offset is counted back from the end.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.image], onCompletion: handleImport)
    }

    private var thumbnailSection: some View {
        VStack(spacing: 6) {
            Thumbnail(data: favorite.thumbnail, size: Self.thumbnailSize)
                .overlay {
                    RoundedRectangle(cornerRadius: Self.thumbnailSize * Self.cornerRadiusScale)
                        .strokeBorder(isDropTargeted ? Color.accentColor : .clear, lineWidth: 2)
                }
                .onDrop(of: [UTType.image], isTargeted: $isDropTargeted, perform: handleDrop)
            HStack(spacing: 6) {
                Button("Paste Image") { pasteThumbnail() }
                Button("Choose Image…") { showImporter = true }
            }
            .controlSize(.small)
            if favorite.hasCustomThumbnail == true {
                Button("Reset to default") { resetThumbnail() }
                    .controlSize(.small)
            }
            if let message {
                Text(message).font(.caption2).foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func timeRow(title: String, time: Binding<TimeInterval?>) -> some View {
        HStack(spacing: 4) {
            Text(title)
            Spacer()
            IntegerField(value: minutesBinding(time), range: 0...999)
            Text("min")
                .font(.caption2)
                .foregroundStyle(.secondary)
            IntegerField(value: secondsBinding(time), range: 0...59)
            Text("s")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func minutesBinding(_ time: Binding<TimeInterval?>) -> Binding<Int> {
        Binding(
            get: { Int(time.wrappedValue ?? 0) / 60 },
            set: { setTime(time, minutes: max(0, $0), seconds: Int(time.wrappedValue ?? 0) % 60) }
        )
    }

    private func secondsBinding(_ time: Binding<TimeInterval?>) -> Binding<Int> {
        Binding(
            get: { Int(time.wrappedValue ?? 0) % 60 },
            set: { setTime(time, minutes: Int(time.wrappedValue ?? 0) / 60, seconds: min(max($0, 0), 59)) }
        )
    }

    /// 0:00 is stored as nil (no trim).
    private func setTime(_ time: Binding<TimeInterval?>, minutes: Int, seconds: Int) {
        let total = minutes * 60 + seconds
        time.wrappedValue = total == 0 ? nil : TimeInterval(total)
    }

    private func pasteThumbnail() {
        guard let data = Clipboard.imageData else {
            message = "No image on the clipboard."
            return
        }
        applyCustomThumbnail(data)
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            guard let data = try? Data(contentsOf: url) else {
                message = "Couldn't read that file."
                return
            }
            applyCustomThumbnail(data)
        case .failure(let error):
            message = error.localizedDescription
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard
            let provider = providers.first(where: {
                $0.hasItemConformingToTypeIdentifier(UTType.image.identifier)
            })
        else { return false }

        provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
            DispatchQueue.main.async {
                guard let data else {
                    message = "Couldn't read the dropped image."
                    return
                }
                applyCustomThumbnail(data)
            }
        }
        return true
    }

    /// Applies a custom image everywhere the track appears: the favorite, its
    /// recent entry, and the Now Playing card when it is the current track.
    private func applyCustomThumbnail(_ data: Data) {
        guard let canonical = favorites.setCustomThumbnail(data, for: favorite.id) else {
            message = "That doesn't look like an image."
            return
        }
        message = nil
        recents.setCustomThumbnail(canonical, for: favorite.url)
        player.applyArtwork(canonical, for: favorite.url, custom: true)
    }

    private func resetThumbnail() {
        favorites.clearCustomThumbnail(for: favorite.id)
        recents.clearCustomThumbnail(for: favorite.url)
        player.applyArtwork(nil, for: favorite.url, custom: false)
        message = nil
        refetchThumbnail()
    }

    /// Re-fetches the automatic artwork and applies it everywhere.
    private func refetchThumbnail() {
        let url = favorite.url
        guard !url.isEmpty else { return }
        Task { @MainActor in
            guard let data = await StreamResolver.thumbnail(for: url) else { return }
            favorites.setThumbnail(data, for: url)
            recents.setThumbnail(data, for: url)
            player.applyArtwork(data, for: url, custom: false)
        }
    }
}
