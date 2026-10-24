import XCTest

final class ICalendarTests: XCTestCase {
    private let ics = """
    BEGIN:VCALENDAR
    BEGIN:VEVENT
    DTSTART;VALUE=DATE:20261023
    DTEND;VALUE=DATE:20261024
    SUMMARY:Cycle 3\\, Day 4
    END:VEVENT
    BEGIN:VEVENT
    DTSTART:20261023T010000Z
    DTEND:20261023T020000Z
    SUMMARY:Staff meeting (fol
     ded title)
    END:VEVENT
    BEGIN:VEVENT
    DTSTART:20261023T030000Z
    SUMMARY:Cancelled thing
    STATUS:CANCELLED
    END:VEVENT
    BEGIN:VEVENT
    DTSTART;TZID=Asia/Hong_Kong:20261019T170000
    DTEND;TZID=Asia/Hong_Kong:20261019T180000
    RRULE:FREQ=WEEKLY;BYDAY=MO,FR;UNTIL=20261231T000000Z
    SUMMARY:Club
    END:VEVENT
    END:VCALENDAR
    """

    private func dayStart(_ compact: String) -> Date {
        ICalendar.parseDate(compact, params: [:])!.0
    }

    private var events: [CalendarEvent] { ICalendar.parse(ics, calendar: "事項") }

    func testParseSkipsCancelledAndUnfoldsLines() {
        XCTAssertEqual(events.count, 3)
        XCTAssertTrue(events.contains { $0.title == "Staff meeting (folded title)" })
        XCTAssertTrue(events.contains { $0.title == "Cycle 3, Day 4" })
    }

    func testOccurrencesOnDayPutAllDayFirst() {
        let items = ICalendar.occurrences(of: events, onDayStarting: dayStart("20261023"))
        XCTAssertEqual(items.map(\.title), ["Cycle 3, Day 4", "Staff meeting (folded title)", "Club"])
        XCTAssertTrue(items[0].allDay)
        let calendar = ICalendar.hongKong
        XCTAssertEqual(calendar.component(.hour, from: items[1].start), 9)
        XCTAssertEqual(calendar.component(.hour, from: items[2].start), 17)
    }

    func testAllDayEventEndIsExclusive() {
        let items = ICalendar.occurrences(of: events, onDayStarting: dayStart("20261024"))
        XCTAssertTrue(items.isEmpty)
    }

    func testWeeklyRuleFollowsByDayAndUntil() {
        XCTAssertTrue(ICalendar.occurrences(of: events, onDayStarting: dayStart("20261021")).isEmpty)
        XCTAssertEqual(ICalendar.occurrences(of: events, onDayStarting: dayStart("20261026")).map(\.title), ["Club"])
        XCTAssertTrue(ICalendar.occurrences(of: events, onDayStarting: dayStart("20270104")).isEmpty)
        XCTAssertTrue(ICalendar.occurrences(of: events, onDayStarting: dayStart("20261016")).isEmpty)
    }

    func testRelevantKeepsRecurringAndNearEvents() {
        let now = dayStart("20261023")
        let old = CalendarEvent(title: "old", start: now.addingTimeInterval(-400 * 86_400), end: now.addingTimeInterval(-399 * 86_400), allDay: true, calendar: "x", rule: nil)
        let kept = ICalendar.relevant(events + [old], around: now)
        XCTAssertEqual(kept.count, events.count)
    }

    func testNextHolidayMergesConsecutiveDays() {
        let today = dayStart("20261023")
        func holiday(_ title: String, _ from: String, _ to: String, calendar: String = SchoolCalendars.holidayName) -> CalendarEvent {
            CalendarEvent(title: title, start: dayStart(from), end: dayStart(to), allDay: true, calendar: calendar, rule: nil)
        }
        let list = [
            holiday("今日放假", "20261023", "20261024"),
            holiday("重陽節翌日", "20261026", "20261027"),
            holiday("聖誕節", "20261225", "20261228"),
            holiday("學校旅行", "20261101", "20261102", calendar: "事項"),
        ]
        let next = ICalendar.nextHoliday(of: list, after: today)
        XCTAssertEqual(next?.title, "重陽節翌日")
        XCTAssertEqual(next?.daysAway, 3)
        XCTAssertEqual(next?.rangeText, "10/26")
        XCTAssertNil(ICalendar.nextHoliday(of: [list[3]], after: today))
        let christmas = ICalendar.nextHoliday(of: [list[2]], after: today)
        XCTAssertEqual(christmas?.rangeText, "12/25–12/27")
        XCTAssertNil(ICalendar.nextHoliday(of: [], after: today))
    }

    func testSchoolCalendarURLEncodesAt() throws {
        let source = try XCTUnwrap(SchoolCalendars.sources.first)
        let url = try XCTUnwrap(SchoolCalendars.url(source))
        XCTAssertTrue(url.absoluteString.hasSuffix("/public/basic.ics"))
        XCTAssertTrue(url.absoluteString.contains("%40group.calendar.google.com"))
        XCTAssertEqual(SchoolCalendars.sources.count, 4)
    }

    func testParseDateVariants() {
        XCTAssertEqual(ICalendar.parseDate("20261023T010000Z", params: [:])?.0, ISO8601DateFormatter().date(from: "2026-10-23T01:00:00Z"))
        XCTAssertEqual(ICalendar.parseDate("20261023T090000", params: [:])?.0, ISO8601DateFormatter().date(from: "2026-10-23T01:00:00Z"))
        XCTAssertEqual(ICalendar.parseDate("20261023", params: ["VALUE": "DATE"])?.1, true)
        XCTAssertNil(ICalendar.parseDate("garbage", params: [:]))
    }
}
