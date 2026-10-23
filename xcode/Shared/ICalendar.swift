import Foundation

/// 一個日曆事件（含基本重複規則）。
struct CalendarEvent: Codable, Equatable {
    var title: String
    var start: Date
    var end: Date
    var allDay: Bool
    var calendar: String
    var rule: RecurrenceRule?
}

/// 基本 RRULE：DAILY／WEEKLY（BYDAY）／MONTHLY／YEARLY ＋ INTERVAL、UNTIL。唔支援 COUNT、EXDATE。
struct RecurrenceRule: Codable, Equatable {
    var freq: String
    var interval: Int
    var until: Date?
    var byDay: [Int]
}

struct CalendarOccurrence: Equatable {
    var title: String
    var start: Date
    var end: Date
    var allDay: Bool
    var calendar: String
}

/// 學校嘅四個公開 Google 日曆（網頁已公開，唔係憑證），經公開 iCal 位址讀取，唔使登入。
enum SchoolCalendars {
    struct Source {
        let name: String
        let id: String
    }

    static let cycleName = "循環周"

    static let sources = [
        Source(name: "事項", id: "skhsslmc.edu.hk_01rudpgarigvp0ivcbe83712hk@group.calendar.google.com"),
        Source(name: "假期", id: "skhsslmc.edu.hk_5k7g1ubf9dqnlvn7fegnkuj3h0@group.calendar.google.com"),
        Source(name: "考試及統測", id: "skhsslmc.edu.hk_4j27jtnq3nf3difmm0pgh0t11c@group.calendar.google.com"),
        Source(name: cycleName, id: "skhsslmc.edu.hk_2cls6pqrhan0n4uvufp97uhhpk@group.calendar.google.com"),
    ]

    static func url(_ source: Source) -> URL? {
        let id = source.id.replacingOccurrences(of: "@", with: "%40")
        return URL(string: "https://calendar.google.com/calendar/ical/\(id)/public/basic.ics")
    }
}

enum ICalendar {
    private struct Property {
        var params: [String: String]
        var value: String
    }

    static var hongKong: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Hong_Kong")!
        return calendar
    }

    // MARK: 解析

    static func parse(_ text: String, calendar name: String) -> [CalendarEvent] {
        var events: [CalendarEvent] = []
        var current: [String: Property]?
        for line in unfold(text) {
            if line == "BEGIN:VEVENT" {
                current = [:]
            } else if line == "END:VEVENT" {
                if let properties = current, let event = makeEvent(properties, calendar: name) { events.append(event) }
                current = nil
            } else if current != nil, let (key, property) = splitProperty(line), current?[key] == nil {
                current?[key] = property
            }
        }
        return events
    }

    private static func unfold(_ text: String) -> [String] {
        let normalised = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n ", with: "")
            .replacingOccurrences(of: "\n\t", with: "")
        return normalised.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }

    private static func splitProperty(_ line: String) -> (String, Property)? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let head = line[..<colon].split(separator: ";", omittingEmptySubsequences: false).map(String.init)
        guard let name = head.first, !name.isEmpty else { return nil }
        var params: [String: String] = [:]
        for part in head.dropFirst() {
            let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
            if pair.count == 2 { params[pair[0].uppercased()] = pair[1] }
        }
        return (name.uppercased(), Property(params: params, value: String(line[line.index(after: colon)...])))
    }

    private static func unescape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\n", with: " ")
            .replacingOccurrences(of: "\\N", with: " ")
            .replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    private static func makeEvent(_ properties: [String: Property], calendar name: String) -> CalendarEvent? {
        if properties["STATUS"]?.value.uppercased() == "CANCELLED" { return nil }
        guard let startProperty = properties["DTSTART"],
              let (start, allDay) = parseDate(startProperty.value, params: startProperty.params) else { return nil }
        var end = start
        if let endProperty = properties["DTEND"], let (parsed, _) = parseDate(endProperty.value, params: endProperty.params) {
            end = parsed
        } else if allDay {
            end = hongKong.date(byAdding: .day, value: 1, to: start) ?? start
        }
        return CalendarEvent(
            title: unescape(properties["SUMMARY"]?.value ?? ""),
            start: start,
            end: max(end, start),
            allDay: allDay,
            calendar: name,
            rule: properties["RRULE"].flatMap { parseRule($0.value) }
        )
    }

    private static func formatter(_ format: String, _ zone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = format
        return formatter
    }

    private static let hkZone = TimeZone(identifier: "Asia/Hong_Kong")!
    private static let utcZone = TimeZone(identifier: "UTC")!

    /// `20261023`（全日）、`20261023T093000Z`、`20261023T093000`（可帶 TZID，冇就當香港時間）。
    static func parseDate(_ value: String, params: [String: String]) -> (Date, Bool)? {
        let text = value.trimmingCharacters(in: .whitespaces)
        if params["VALUE"] == "DATE" || text.count == 8 {
            return formatter("yyyyMMdd", hkZone).date(from: String(text.prefix(8))).map { ($0, true) }
        }
        let utc = text.hasSuffix("Z")
        let body = utc ? String(text.dropLast()) : text
        let zone = utc ? utcZone : (params["TZID"].flatMap { TimeZone(identifier: $0) } ?? hkZone)
        return formatter("yyyyMMdd'T'HHmmss", zone).date(from: body).map { ($0, false) }
    }

    private static func parseRule(_ text: String) -> RecurrenceRule? {
        var values: [String: String] = [:]
        for part in text.split(separator: ";") {
            let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
            if pair.count == 2 { values[pair[0].uppercased()] = pair[1] }
        }
        guard let freq = values["FREQ"]?.uppercased(), ["DAILY", "WEEKLY", "MONTHLY", "YEARLY"].contains(freq) else { return nil }
        let weekdays = ["SU": 1, "MO": 2, "TU": 3, "WE": 4, "TH": 5, "FR": 6, "SA": 7]
        let byDay = (values["BYDAY"] ?? "").split(separator: ",").compactMap { weekdays[String($0.suffix(2))] }
        let until = values["UNTIL"].flatMap { parseDate($0, params: [:])?.0 }
        return RecurrenceRule(freq: freq, interval: max(Int(values["INTERVAL"] ?? "") ?? 1, 1), until: until, byDay: byDay)
    }

    // MARK: 某日嘅事件

    /// 喺 `dayStart`（當日 00:00）嗰日出現嘅事件。全日事件排先，之後按開始時間。
    static func occurrences(of events: [CalendarEvent], onDayStarting dayStart: Date, calendar: Calendar = hongKong) -> [CalendarOccurrence] {
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        var result: [CalendarOccurrence] = []
        for event in events {
            guard let occurrence = occurrence(of: event, dayStart: dayStart, dayEnd: dayEnd, calendar: calendar) else { continue }
            if !result.contains(where: { $0.title == occurrence.title && $0.start == occurrence.start && $0.calendar == occurrence.calendar }) {
                result.append(occurrence)
            }
        }
        return result.sorted { lhs, rhs in
            if lhs.allDay != rhs.allDay { return lhs.allDay }
            return lhs.start < rhs.start
        }
    }

    private static func occurrence(of event: CalendarEvent, dayStart: Date, dayEnd: Date, calendar: Calendar) -> CalendarOccurrence? {
        func make(_ start: Date, _ end: Date) -> CalendarOccurrence {
            CalendarOccurrence(title: event.title, start: start, end: end, allDay: event.allDay, calendar: event.calendar)
        }
        guard let rule = event.rule else {
            let instant = event.end == event.start
            let overlaps = instant ? (event.start >= dayStart && event.start < dayEnd) : (event.start < dayEnd && event.end > dayStart)
            return overlaps ? make(event.start, event.end) : nil
        }

        let baseDay = calendar.startOfDay(for: event.start)
        guard dayStart >= baseDay, rule.until.map({ dayStart <= $0 }) ?? true else { return nil }
        let days = calendar.dateComponents([.day], from: baseDay, to: dayStart).day ?? 0
        let matches: Bool
        switch rule.freq {
        case "DAILY":
            matches = days % rule.interval == 0
        case "WEEKLY":
            let weekdays = rule.byDay.isEmpty ? [calendar.component(.weekday, from: baseDay)] : rule.byDay
            matches = weekdays.contains(calendar.component(.weekday, from: dayStart)) && (days / 7) % rule.interval == 0
        case "MONTHLY":
            let months = calendar.dateComponents([.month], from: baseDay, to: dayStart).month ?? 0
            matches = calendar.component(.day, from: dayStart) == calendar.component(.day, from: baseDay) && months % rule.interval == 0
        default:
            matches = calendar.component(.day, from: dayStart) == calendar.component(.day, from: baseDay)
                && calendar.component(.month, from: dayStart) == calendar.component(.month, from: baseDay)
        }
        guard matches else { return nil }
        let start = dayStart.addingTimeInterval(event.start.timeIntervalSince(baseDay))
        return make(start, start.addingTimeInterval(event.end.timeIntervalSince(event.start)))
    }

    /// 只留今日前後嘅事件（重複事件照留），避免快取成年歷史。
    static func relevant(_ events: [CalendarEvent], around now: Date, days: Int = 60) -> [CalendarEvent] {
        let from = now.addingTimeInterval(-86_400)
        let to = now.addingTimeInterval(Double(days) * 86_400)
        return events.filter { $0.rule != nil || ($0.end >= from && $0.start <= to) }
    }
}
