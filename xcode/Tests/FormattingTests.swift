import XCTest

final class FormattingTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    func testBytesUseDecimalUnits() {
        XCTAssertEqual(Formatting.bytes(128_000_000_000), "128.0 GB")
        XCTAssertEqual(Formatting.bytes(999), "999 B")
        XCTAssertEqual(Formatting.bytes(1_500), "2 KB")
        XCTAssertEqual(Formatting.bytes(1_000_000_000_000), "1.00 TB")
        XCTAssertEqual(Formatting.bytes(nil), "—")
    }

    func testStoragePairWritesUnitOnce() {
        XCTAssertEqual(Formatting.storagePair(free: 32_600_000_000, total: 255_400_000_000), "32.6 / 255.4 GB")
        XCTAssertEqual(Formatting.storagePair(free: 500_000_000, total: 255_400_000_000), "500 MB / 255.4 GB")
        XCTAssertEqual(Formatting.storagePair(free: nil, total: nil), "—")
        XCTAssertEqual(Formatting.storagePair(free: 1_000_000_000, total: nil), "1.0 GB")
    }

    func testUptime() {
        XCTAssertEqual(Formatting.uptime(90_061), "1 天 1 小時")
        XCTAssertEqual(Formatting.uptime(3_700), "1 小時 1 分")
        XCTAssertEqual(Formatting.uptime(59), "0 分")
        XCTAssertEqual(Formatting.uptime(nil), "—")
        XCTAssertEqual(Formatting.uptime(-5), "—")
    }

    func testPercent() {
        XCTAssertEqual(Formatting.percent(0.75), "75%")
        XCTAssertEqual(Formatting.percent(1), "100%")
        XCTAssertEqual(Formatting.percent(nil), "—")
    }

    func testDateStrings() {
        let friday = date(2026, 10, 23, 14, 5)
        XCTAssertEqual(Formatting.weekday(friday, calendar: calendar), "星期五")
        XCTAssertEqual(Formatting.monthDay(friday, calendar: calendar), "10月23日")
        XCTAssertEqual(Formatting.clock(friday, calendar: calendar), "14:05")
        XCTAssertEqual(Formatting.clock(date(2026, 10, 23, 0, 7), calendar: calendar), "00:07")
        XCTAssertEqual(Formatting.weekday(date(2026, 10, 25), calendar: calendar), "星期日")
    }

    func testStorageFractions() {
        XCTAssertEqual(Formatting.usedFraction(free: 25, total: 100)!, 0.75, accuracy: 0.0001)
        XCTAssertNil(Formatting.usedFraction(free: nil, total: 100))
        XCTAssertNil(Formatting.usedFraction(free: 10, total: 0))
        XCTAssertTrue(Formatting.isLowStorage(free: 5, total: 100))
        XCTAssertFalse(Formatting.isLowStorage(free: 10, total: 100))
        XCTAssertFalse(Formatting.isLowStorage(free: nil, total: 100))
    }
}
