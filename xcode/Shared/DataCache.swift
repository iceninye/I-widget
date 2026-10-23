import Foundation

/// 最後一次成功嘅網絡資料，離線或者請求失敗時照用。存喺進程自己嘅 UserDefaults
/// （widget extension 同 app 各有一份，唔使 App Group）。
enum DataCache {
    static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: "cache.\(key)") else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: "cache.\(key)")
    }
}

enum Fetcher {
    static func data(from url: URL, timeout: TimeInterval = 8) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}
