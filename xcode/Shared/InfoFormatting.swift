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

    /// 超過呢段時間冇更新，就當資料已過時。
    static let staleAfter: TimeInterval = 3_600

    static func isStale(_ date: Date?, now: Date) -> Bool {
        guard let date else { return true }
        return now.timeIntervalSince(date) > staleAfter
    }
}
