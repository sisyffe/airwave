import Foundation

struct Favorite: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var url: String
    var thumbnail: Data? = nil
}

@MainActor
final class FavoritesStore: ObservableObject {
    @Published var items: [Favorite] = [] { didSet { save() } }
    private let key = "favorites"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([Favorite].self, from: data) {
            items = decoded
        }
    }

    func add(name: String, url: String, thumbnail: Data? = nil) {
        guard !items.contains(where: { $0.url == url }) else { return }
        items.append(Favorite(name: name.isEmpty ? url : name, url: url, thumbnail: thumbnail))
    }

    /// Fill in a missing thumbnail once one is known (e.g. after playing).
    func setThumbnail(_ data: Data, for url: String) {
        guard let i = items.firstIndex(where: { $0.url == url }), items[i].thumbnail == nil else { return }
        items[i].thumbnail = data
    }

    func favorite(for url: String) -> Favorite? { items.first { $0.url == url } }
    func remove(_ fav: Favorite) { items.removeAll { $0.id == fav.id } }

    func rename(_ fav: Favorite, to name: String) {
        guard let i = items.firstIndex(where: { $0.id == fav.id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        items[i].name = trimmed.isEmpty ? items[i].url : trimmed
    }
    func contains(url: String) -> Bool { items.contains { $0.url == url } }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
