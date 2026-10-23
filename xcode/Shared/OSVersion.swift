import Foundation

enum OSVersionStatus: Equatable {
    case unknown
    case upToDate
    case updateAvailable(String)
}

/// iOS 版本比較同「最新版本」解析。冇 UIKit，方便單元測試。
enum OSVersion {
    /// endoflife.date 嘅 iOS 資料：每個大版本一個物件，`latest` 係該版本最新小版本。
    static let latestURL = URL(string: "https://endoflife.date/api/ios.json")!

    static func components(_ version: String) -> [Int] {
        version.split(separator: ".").compactMap { Int($0) }
    }

    static func isNewer(_ latest: String, than current: String) -> Bool {
        let a = components(latest)
        let b = components(current)
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }

    private struct Cycle: Decodable { let latest: String? }

    /// 全部大版本入面最高嘅 `latest`。
    static func parseLatest(_ data: Data) throws -> String {
        let cycles = try JSONDecoder().decode([Cycle].self, from: data)
        let versions = cycles.compactMap(\.latest).filter { !components($0).isEmpty }
        guard var best = versions.first else { throw URLError(.cannotParseResponse) }
        for version in versions.dropFirst() where isNewer(version, than: best) { best = version }
        return best
    }

    static func status(current: String, latest: String?) -> OSVersionStatus {
        guard let latest, !components(latest).isEmpty else { return .unknown }
        return isNewer(latest, than: current) ? .updateAvailable(latest) : .upToDate
    }
}
