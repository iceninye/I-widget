import Foundation

struct VPSState {
    var status: VPSStatus?
    var configured: Bool
    var failed: Bool

    static let sample = VPSState(status: .sample, configured: true, failed: false)

    static func isConfigured(url: String?, token: String?) -> Bool {
        VPSAPI.statusURL(url) != nil && !(token ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func cached(url: String?, token: String?) -> VPSState {
        VPSState(status: DataCache.load(VPSStatus.self, key: "vps"), configured: isConfigured(url: url, token: token), failed: false)
    }

    /// VPS 腳本每小時更新一次，所以 25 分鐘內讀過就用快取。
    static func load(url text: String?, token: String?, now: Date) async -> VPSState {
        guard isConfigured(url: text, token: token), let url = VPSAPI.statusURL(text) else {
            return VPSState(status: nil, configured: false, failed: false)
        }
        let cached = DataCache.load(VPSStatus.self, key: "vps")
        if let fresh = DataCache.fresh(VPSStatus.self, key: "vps", maxAge: 25 * 60, now: now) {
            return VPSState(status: fresh, configured: true, failed: false)
        }
        let bearer = (token ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let failed = VPSState(status: cached, configured: true, failed: true)
        return await withDeadline(12, fallback: failed) {
            do {
                var request = URLRequest(url: url, timeoutInterval: 10)
                request.cachePolicy = .reloadIgnoringLocalCacheData
                request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    throw URLError(.badServerResponse)
                }
                let status = try VPSAPI.parse(data)
                DataCache.save(status, key: "vps", stamped: now)
                return VPSState(status: status, configured: true, failed: false)
            } catch {
                return failed
            }
        }
    }
}
