import Foundation

/// 天氣、黃金、版本嘅顯示字串。
extension Formatting {
    static func degrees(_ value: Double?) -> String {
        guard let value else { return missing }
        return "\(Int(value.rounded()))°"
    }

    /// 「24–28°」。
    static func tempRange(_ day: WeatherDay?) -> String {
        guard let day else { return missing }
        return "\(Int(day.minTemp.rounded()))–\(Int(day.maxTemp.rounded()))°"
    }

    /// 2,345.68
    static func gold(_ price: Double?) -> String {
        guard let price else { return missing }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: price)) ?? missing
    }

    /// 26,123（港元每両：整數已經夠，細格放得落）
    static func goldWhole(_ price: Double?) -> String {
        guard let price else { return missing }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: price.rounded())) ?? missing
    }

    /// 超過呢段時間冇更新，就當資料已過時。
    static let staleAfter: TimeInterval = 3_600

    static func isStale(_ date: Date?, now: Date) -> Bool {
        guard let date else { return true }
        return now.timeIntervalSince(date) > staleAfter
    }

    /// 「最後成功取得資料」嘅時間；nil 係「從來冇成功讀到」，要講明，唔好當做啱啱更新。
    static func lastUpdated(_ date: Date?) -> String {
        date.map { Formatting.clock($0) } ?? "未有資料"
    }

    /// 大細格用嘅短時長：「3天5時」「5時12分」「12分」；比 `uptime` 短，加大字級都放得落。
    static func shortDuration(_ seconds: TimeInterval?) -> String {
        guard let seconds, seconds >= 0 else { return missing }
        let total = Int(seconds)
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        if days > 0 { return "\(days)天\(hours)時" }
        if hours > 0 { return "\(hours)時\(minutes)分" }
        return "\(minutes)分"
    }
}
