import Foundation

/// 伺服器狀態：VPS 上嘅腳本每小時輸出一個只讀 JSON，widget 用 Bearer token 讀。
struct VPSStatus: Codable, Equatable {
    var os: String
    var kernel: String
    var upgradable: Int
    var security: Int
    var rebootRequired: Bool
    var xrayRunning: Bool?
    var hysteria2Listening: Bool?
    var updatedAt: Date?

    static let sample = VPSStatus(
        os: "Ubuntu 24.04.3 LTS", kernel: "6.8.0-48-generic", upgradable: 3, security: 1,
        rebootRequired: false, xrayRunning: true, hysteria2Listening: true, updatedAt: Date()
    )
}

enum VPSHealth: Equatable {
    case ok, attention, problem
}

enum VPSAPI {
    /// Ice 嘅 VPS 狀態網址（Ice 要求寫入程式）；token 仍然要喺 widget 設定手動輸入。
    static let defaultURL = URL(string: "https://n8n.itswong.site/status.json")!

    /// widget 設定有填網址就用佢，留空就用預設。
    static func statusURL(_ text: String?) -> URL? {
        let trimmed = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultURL : url(trimmed)
    }

    /// 只收 https，並去走前後空白。
    static func url(_ text: String?) -> URL? {
        let trimmed = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("https://"), let url = URL(string: trimmed), url.host != nil else { return nil }
        return url
    }

    private struct Raw: Decodable {
        let os: String?
        let kernel: String?
        let upgradable: Int?
        let security: Int?
        let rebootRequired: Bool?
        let xrayRunning: Bool?
        let hysteria2Listening: Bool?
        let updatedAt: String?
    }

    static func parse(_ data: Data) throws -> VPSStatus {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let raw = try decoder.decode(Raw.self, from: data)
        guard let os = raw.os, let upgradable = raw.upgradable else { throw URLError(.cannotParseResponse) }
        return VPSStatus(
            os: os,
            kernel: raw.kernel ?? "",
            upgradable: upgradable,
            security: raw.security ?? 0,
            rebootRequired: raw.rebootRequired ?? false,
            xrayRunning: raw.xrayRunning,
            hysteria2Listening: raw.hysteria2Listening,
            updatedAt: raw.updatedAt.flatMap(parseTime)
        )
    }

    /// 腳本輸出 UTC ISO 時間（可能帶 6 位小數），只取到秒。
    static func parseTime(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.date(from: String(text.prefix(19)))
    }

    static func health(_ status: VPSStatus) -> VPSHealth {
        if status.security > 0 || status.rebootRequired || status.xrayRunning == false || status.hysteria2Listening == false {
            return .problem
        }
        return status.upgradable > 0 ? .attention : .ok
    }

    static func updatesText(_ status: VPSStatus) -> String {
        if status.upgradable == 0 { return "已是最新" }
        return status.security > 0 ? "\(status.upgradable) 項更新（\(status.security) 項安全）" : "\(status.upgradable) 項更新"
    }
}
