import Foundation

/// 個人更表：每行一個星期（週一至週日 7 格），循環；`anchor` 記「某個星期一做第幾行」。
/// 邏輯同 tml-roster `lib/tml-roster.js` 一致（只讀，唔會寫返雲端）。
struct Roster: Codable, Equatable {
    var rows: [[String]]
    var numbers: [Int]
    var anchorRow: Int
    var anchorMonday: String
    var overrides: [String: String]
}

struct RosterEntry: Equatable {
    var code: String
    var isOverride: Bool
    var row: Int
}

/// 以 UTC 日數計日期（同 JS 版一樣），避免時區同夏令時間問題。日期格式 `YYYY-MM-DD`。
enum Days {
    private static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    static func number(_ date: String) -> Int? {
        let parts = date.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        guard let value = utc.date(from: components) else { return nil }
        return Int((value.timeIntervalSince1970 / 86_400).rounded())
    }

    static func string(_ number: Int) -> String {
        let value = Date(timeIntervalSince1970: Double(number) * 86_400)
        let parts = utc.dateComponents([.year, .month, .day], from: value)
        return String(format: "%04d-%02d-%02d", parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1)
    }

    static func add(_ date: String, _ days: Int) -> String? {
        number(date).map { string($0 + days) }
    }

    /// 0 = 星期一 … 6 = 星期日。
    static func weekdayIndex(_ date: String) -> Int? {
        number(date).map { (($0 + 3) % 7 + 7) % 7 }
    }

    static func mondayOf(_ date: String) -> String? {
        guard let number = number(date), let index = weekdayIndex(date) else { return nil }
        return string(number - index)
    }

    /// 香港日曆日（00:00 換日）。
    static func calendarDate(_ now: Date) -> String {
        string(Int(((now.timeIntervalSince1970 + 8 * 3_600) / 86_400).rounded(.down)))
    }

    /// 「今日」：00:00 換日，同 tml-roster 今日卡一致；但 00:00–04:00 如果昨日嗰更仲未放工
    /// （例如 15:34–00:04 夜更），就繼續當昨日。`off` 係某日嘅放工時間（由該日 00:00 起計嘅秒數，可以超過 86400）。
    static func today(_ now: Date, off: (String) -> Int?) -> String {
        let calendar = calendarDate(now)
        let previous = serviceDate(now)
        guard previous != calendar, let offSeconds = off(previous), let day = number(previous) else { return calendar }
        let seconds = now.timeIntervalSince1970 - (Double(day) * 86_400 - 8 * 3_600)
        return seconds < Double(offSeconds) ? previous : calendar
    }

    /// 服務日：香港時間 04:00 轉日，凌晨收工嘅更仍然算前一日。
    static func serviceDate(_ now: Date) -> String {
        let local = now.timeIntervalSince1970 + 8 * 3_600
        var day = (local / 86_400).rounded(.down)
        if local - day * 86_400 < 4 * 3_600 { day -= 1 }
        return string(Int(day))
    }
}

extension Roster {
    private func isPending(_ row: [String]) -> Bool {
        !row.isEmpty && row.allSatisfy { $0 == "TBC" }
    }

    /// `weeks` 個星期之後做第幾行。全部 TBC 嘅行唔參與輪換。
    func rowAfter(_ label: Int, weeks: Int) -> Int? {
        guard let at = numbers.firstIndex(of: label), at < rows.count else { return nil }
        if isPending(rows[at]) { return numbers[at] }
        let cycle = rows.indices.filter { !isPending(rows[$0]) }
        guard let position = cycle.firstIndex(of: at) else { return nil }
        let count = cycle.count
        return numbers[cycle[((position + weeks) % count + count) % count]]
    }

    func rowIndex(monday: String) -> Int? {
        guard let target = Days.number(monday), let anchor = Days.number(anchorMonday) else { return nil }
        let weeks = Int((Double(target - anchor) / 7).rounded())
        guard let label = rowAfter(anchorRow, weeks: weeks) else { return nil }
        return numbers.firstIndex(of: label)
    }

    /// 某日嘅更份格：用戶手動改過就用佢，否則跟輪換。
    func entry(on date: String) -> RosterEntry? {
        guard let monday = Days.mondayOf(date), let index = rowIndex(monday: monday),
              let weekday = Days.weekdayIndex(date), index < rows.count, rows[index].count == 7 else { return nil }
        let own = overrides[date]
        return RosterEntry(code: own ?? rows[index][weekday], isOverride: own != nil, row: numbers[index])
    }
}

/// 雲端同步 API：`GET /api/roster/<token>`。token 等同密碼（攞到條網址嘅人讀寫得到），
/// 所以唔寫入 repo；回應入面嘅人名（`names`）唔解析、唔快取。
enum RosterAPI {
    static let base = "https://tml-roster.iceninye.workers.dev/api/roster/"

    static func cleanToken(_ value: String?) -> String? {
        let token = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return token.range(of: "^[a-z0-9]{20,64}$", options: .regularExpression) == nil ? nil : token
    }

    static func url(token: String?) -> URL? {
        cleanToken(token).flatMap { URL(string: base + $0) }
    }

    private struct Response: Decodable {
        struct Record: Decodable {
            struct Anchor: Decodable {
                let row: Int?
                let monday: String?
            }
            let rows: [[String]]
            let numbers: [Int]?
            let anchor: Anchor?
            let overrides: [String: String]?
        }
        let record: Record
    }

    static func parse(_ data: Data) throws -> Roster {
        let record = try JSONDecoder().decode(Response.self, from: data).record
        let numbers = record.numbers ?? Array(1...max(record.rows.count, 1))
        guard !record.rows.isEmpty, numbers.count == record.rows.count,
              record.rows.allSatisfy({ $0.count == 7 }),
              let row = record.anchor?.row, let monday = record.anchor?.monday,
              Days.number(monday) != nil, numbers.contains(row) else {
            throw URLError(.cannotParseResponse)
        }
        return Roster(
            rows: record.rows.map { $0.map { $0.uppercased() } },
            numbers: numbers,
            anchorRow: row,
            anchorMonday: monday,
            overrides: record.overrides ?? [:]
        )
    }
}

struct DutyTime: Codable, Equatable {
    var on: Int
    var onPlace: String
    var off: Int
    var offPlace: String
    var hours: Double
}

enum ShiftClass: String {
    case dawn = "死早", early = "早", mid = "中", late = "夜", night = "死夜"

    /// 死早：06:30 前上班；死夜：翌日 00:30 後下班；其餘按上班時間 10:00／15:00 分早、中、夜。
    static func of(on: Int, off: Int?) -> ShiftClass {
        if Double(on) < 6.5 * 3_600 { return .dawn }
        if let off, Double(off) > 86_400 + 0.5 * 3_600 { return .night }
        if Double(on) < 10 * 3_600 { return .early }
        return Double(on) < 15 * 3_600 ? .mid : .late
    }
}

/// TML-traffic `data/duty-basic.json`：`"1100101": [上班秒, "地點", 下班秒, "地點", 工時, "DE/DL"]`。
enum DutyBasic {
    static let urls = [
        URL(string: "https://tml-traffic.iceninye.workers.dev/data/duty-basic.json")!,
        URL(string: "https://raw.githubusercontent.com/iceninye/TML-traffic/main/data/duty-basic.json")!,
    ]

    static func parse(_ data: Data) throws -> [String: DutyTime] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let duties = root["duties"] as? [String: [Any]] else { throw URLError(.cannotParseResponse) }
        var result: [String: DutyTime] = [:]
        for (code, value) in duties where value.count >= 5 {
            guard let on = (value[0] as? NSNumber)?.intValue, let off = (value[2] as? NSNumber)?.intValue else { continue }
            result[code] = DutyTime(
                on: on,
                onPlace: value[1] as? String ?? "",
                off: off,
                offPlace: value[3] as? String ?? "",
                hours: (value[4] as? NSNumber)?.doubleValue ?? 0
            )
        }
        return result
    }
}
