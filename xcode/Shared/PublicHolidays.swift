import Foundation

/// 香港公眾假期（政府 1823 嘅 JSON 日曆），只用嚟令法院案件表跳過假期。
enum PublicHolidays {
    static let url = URL(string: "https://www.1823.gov.hk/common/ical/tc.json")

    /// `yyyyMMdd`（香港時間）。
    static func key(_ day: Date, calendar: Calendar = ICalendar.hongKong) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d%02d%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// `{"vcalendar":[{"vevent":[{"dtstart":["20261225",{"value":"DATE"}],...}]}]}` → 日期集合；格式唔啱就係空集合。
    static func parse(_ data: Data) -> Set<String> {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let calendars = root["vcalendar"] as? [[String: Any]] else { return [] }
        var days = Set<String>()
        for calendar in calendars {
            for event in calendar["vevent"] as? [[String: Any]] ?? [] {
                if let start = (event["dtstart"] as? [Any])?.first as? String, start.count >= 8,
                   start.prefix(8).allSatisfy(\.isNumber) {
                    days.insert(String(start.prefix(8)))
                }
            }
        }
        return days
    }

    private static let cacheKey = "publicHolidays"

    static func cached() -> Set<String> {
        DataCache.load(Set<String>.self, key: cacheKey) ?? []
    }

    /// 7 日內讀過就唔再讀；讀唔到就用舊快取（再唔得就當冇假期）。
    static func load(now: Date) async -> Set<String> {
        if let fresh = DataCache.fresh(Set<String>.self, key: cacheKey, maxAge: 7 * 86_400, now: now) { return fresh }
        if let url, let data = try? await Fetcher.data(from: url, timeout: 10) {
            let days = parse(data)
            if !days.isEmpty {
                DataCache.save(days, key: cacheKey, stamped: now)
                return days
            }
        }
        return cached()
    }
}
