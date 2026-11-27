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
    private static let remoteMaxAge: TimeInterval = 30 * 86_400

    /// 2026–2027 官方憲報清單；冷啟動、離線或遠端快取過期時的最終 fallback。
    static let bundled: Set<String> = [
        "20260101", "20260217", "20260218", "20260219",
        "20260403", "20260404", "20260406", "20260407",
        "20260501", "20260525", "20260619", "20260701", "20260926",
        "20261001", "20261019", "20261225", "20261226",
        "20270101", "20270206", "20270208", "20270209",
        "20270326", "20270327", "20270329", "20270405",
        "20270501", "20270513", "20270609", "20270701", "20270916",
        "20271001", "20271008", "20271225", "20271227",
    ]

    static func resolved(cached: Set<String>?, savedAt: Date?, now: Date) -> Set<String> {
        guard let cached, let savedAt, savedAt <= now, now.timeIntervalSince(savedAt) < remoteMaxAge else {
            return bundled
        }
        return cached.union(bundled)
    }

    static func cached(now: Date = Date()) -> Set<String> {
        resolved(cached: DataCache.load(Set<String>.self, key: cacheKey), savedAt: DataCache.savedAt(cacheKey), now: now)
    }

    /// 7 日內讀過就唔再讀；讀唔到就用未過 30 日嘅遠端快取，再唔得用內嵌清單。
    /// `force` 只由手動刷新傳入，繞過 7 日新鮮度檢查。
    static func load(now: Date, force: Bool = false) async -> Set<String> {
        if !force, let fresh = DataCache.fresh(Set<String>.self, key: cacheKey, maxAge: 7 * 86_400, now: now) {
            return resolved(cached: fresh, savedAt: DataCache.savedAt(cacheKey), now: now)
        }
        if let url, let data = try? await Fetcher.data(from: url, timeout: 10) {
            let days = parse(data)
            if !days.isEmpty {
                DataCache.save(days, key: cacheKey, stamped: now)
                return resolved(cached: days, savedAt: now, now: now)
            }
        }
        return cached(now: now)
    }
}
