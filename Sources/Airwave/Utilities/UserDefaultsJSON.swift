import Foundation

/// Persists `Codable` values as JSON in `UserDefaults`.
///
/// Used by the favorites and recents stores so their persistence logic lives in
/// one place and stays consistent.
enum UserDefaultsJSON {
    static func load<Value: Decodable>(
        _ type: Value.Type,
        from key: String,
        defaults: UserDefaults = .standard
    ) -> Value? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func save<Value: Encodable>(
        _ value: Value,
        to key: String,
        defaults: UserDefaults = .standard
    ) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
