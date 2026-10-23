import Foundation

/// 顯示用字串。全部係純函式，同 Pyto／Scriptable 版本嘅格式一致，方便單元測試。
enum Formatting {
    static let missing = "—"

    /// `Calendar.weekday`：1 = 星期日。
    static let weekdays = ["星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六"]

    static func weekday(_ date: Date, calendar: Calendar = .current) -> String {
        let index = calendar.component(.weekday, from: date) - 1
        return weekdays[min(max(index, 0), weekdays.count - 1)]
    }

    static func monthDay(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.month, .day], from: date)
        return "\(parts.month ?? 0)月\(parts.day ?? 0)日"
    }

    /// 24 小時制 `HH:mm`。唔用系統 locale，避免 12 小時制顯示成 `1:30 AM`。
    static func clock(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02ld:%02ld", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// 十進制單位（1 GB = 1000³），同 iOS「設定」顯示一致。
    static func bytes(_ value: Int64?) -> String {
        guard let value else { return missing }
        var size = Double(value)
        for unit in ["B", "KB", "MB"] {
            if size < 1000 { return "\(String(format: "%.0f", size)) \(unit)" }
            size /= 1000
        }
        if size < 1000 { return "\(String(format: "%.1f", size)) GB" }
        return "\(String(format: "%.2f", size / 1000)) TB"
    }

    /// 「32.6 / 255.4 GB」：單位相同就只寫一次。
    static func storagePair(free: Int64?, total: Int64?) -> String {
        let used = bytes(free)
        guard let total else { return used }
        let whole = bytes(total)
        if used != missing, let usedUnit = used.split(separator: " ").last,
           let wholeUnit = whole.split(separator: " ").last, usedUnit == wholeUnit {
            let number = used.split(separator: " ").dropLast().joined(separator: " ")
            return "\(number) / \(whole)"
        }
        return "\(used) / \(whole)"
    }

    static func uptime(_ seconds: TimeInterval?) -> String {
        guard let seconds, seconds >= 0 else { return missing }
        let total = Int(seconds)
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        if days > 0 { return "\(days) 天 \(hours) 小時" }
        if hours > 0 { return "\(hours) 小時 \(minutes) 分" }
        return "\(minutes) 分"
    }

    static func percent(_ fraction: Double?) -> String {
        guard let fraction else { return missing }
        return "\(Int((fraction * 100).rounded()))%"
    }

    /// 可用空間低過呢個比例就轉紅。
    static let lowStorageRatio = 0.1

    static func usedFraction(free: Int64?, total: Int64?) -> Double? {
        guard let free, let total, total > 0 else { return nil }
        return min(max(1 - Double(free) / Double(total), 0), 1)
    }

    static func isLowStorage(free: Int64?, total: Int64?) -> Bool {
        guard let free, let total, total > 0 else { return false }
        return Double(free) / Double(total) < lowStorageRatio
    }
}
