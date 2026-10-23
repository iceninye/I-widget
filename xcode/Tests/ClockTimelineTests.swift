import XCTest

final class ClockTimelineTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    func testMinuteDatesStartAtMinuteBoundaryAndStepByOneMinute() {
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 14, minute: 5, second: 42))!
        let dates = ClockTimeline.minuteDates(from: start, count: 30, calendar: calendar)
        XCTAssertEqual(dates.count, 30)
        XCTAssertEqual(calendar.component(.second, from: dates[0]), 0)
        XCTAssertEqual(calendar.component(.minute, from: dates[0]), 5)
        for index in 1..<dates.count {
            XCTAssertEqual(dates[index].timeIntervalSince(dates[index - 1]), 60, accuracy: 0.001)
        }
    }

    func testMinuteDatesCrossMidnight() {
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 23, minute: 50))!
        let dates = ClockTimeline.minuteDates(from: start, count: 30, calendar: calendar)
        XCTAssertEqual(calendar.component(.day, from: dates.last!), 24)
        XCTAssertEqual(calendar.component(.hour, from: dates.last!), 0)
    }

    func testMinuteDatesWithZeroCountIsEmpty() {
        XCTAssertTrue(ClockTimeline.minuteDates(from: Date(), count: 0).isEmpty)
    }

    func testDayProgress() {
        let midnight = calendar.date(from: DateComponents(year: 2026, month: 10, day: 23))!
        let noon = calendar.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 12))!
        XCTAssertEqual(ClockTimeline.dayProgress(midnight, calendar: calendar), 0, accuracy: 0.0001)
        XCTAssertEqual(ClockTimeline.dayProgress(noon, calendar: calendar), 0.5, accuracy: 0.0001)
    }
}
