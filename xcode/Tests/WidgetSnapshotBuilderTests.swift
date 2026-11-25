import XCTest

final class WidgetSnapshotBuilderTests: XCTestCase {
    func testCourtDateIsConvertedOnlyForExport() {
        XCTAssertEqual(WidgetSnapshotBuilder.exportDateCode("23102026"), "20261023")
        XCTAssertEqual(WidgetSnapshotBuilder.exportDateCode("01012026"), "20260101")
        XCTAssertEqual(WidgetSnapshotBuilder.exportDateCode("invalid"), "invalid")
        XCTAssertEqual(WidgetSnapshotBuilder.exportDateCode("2026102"), "2026102")
    }

    func testCourtFiltersFinishedCasesBeforeApplyingLimit() {
        let now = hongKongDate(2026, 10, 23, 14, 5)
        let finished = (100..<200).map { courtCase(minutes: $0, number: "finished-\($0)") }
        let relevant = (900...980).map { courtCase(minutes: $0, number: "upcoming-\($0)") }
        let day = CourtDay(code: "DC", dateCode: "23102026", total: 181, cases: finished + relevant)

        let exported = WidgetSnapshotBuilder.build(
            entry: entry(at: now),
            courts: [day],
            listDate: ICalendar.hongKong.startOfDay(for: now),
            now: now
        ).courts.items[0]

        XCTAssertEqual(exported.dateCode, "20261023")
        XCTAssertEqual(exported.cases.count, WidgetSchema.maxCasesPerCourt)
        XCTAssertTrue(exported.truncated)
        XCTAssertEqual(exported.cases.first?.caseNo, "upcoming-900")
        XCTAssertEqual(exported.cases.last?.caseNo, "upcoming-979")
        XCTAssertFalse(exported.cases.contains { $0.caseNo.hasPrefix("finished") })
    }

    func testFutureCourtListKeepsAllCasesBeforeLimit() {
        let now = hongKongDate(2026, 10, 23, 19, 0)
        let tomorrow = try! XCTUnwrap(ICalendar.hongKong.date(byAdding: .day, value: 1, to: now))
        let day = CourtDay(
            code: "DC", dateCode: "24102026", total: 2,
            cases: [courtCase(minutes: 540, number: "morning"), courtCase(minutes: 600, number: "later")]
        )

        let exported = WidgetSnapshotBuilder.build(
            entry: entry(at: now), courts: [day], listDate: tomorrow, now: now
        ).courts.items[0]

        XCTAssertEqual(exported.dateCode, "20261024")
        XCTAssertEqual(exported.cases.map(\.caseNo), ["morning", "later"])
        XCTAssertFalse(exported.truncated)
    }

    func testCourtLimitCountsCourts() {
        let now = hongKongDate(2026, 10, 23, 14, 5)
        let codes = ["DC", "ALLMAG", "CFA", "FMC", "LT"]
        let days = codes.map { CourtDay(code: $0, dateCode: "23102026", total: 0, cases: []) }

        let exported = WidgetSnapshotBuilder.build(entry: entry(at: now), courts: days, now: now)

        XCTAssertEqual(exported.courts.items.map(\.code), Array(codes.prefix(WidgetSchema.maxCourts)))
    }

    private func entry(at date: Date) -> OverviewEntry {
        let info = ExtraInfo(
            weather: nil, gold: nil, latestOS: nil, updatedAt: nil,
            warnings: nil, train: nil, air: nil, fx: nil
        )
        return OverviewEntry(
            date: date, stats: .sample, battery: .unknown, info: info,
            schedule: .empty, vps: VPSState(status: nil, configured: false, failed: false),
            updatedAt: nil
        )
    }

    private func courtCase(minutes: Int, number: String) -> CourtCase {
        CourtCase(room: "3", judge: "陳法官", minutes: minutes, caseNo: number)
    }

    private func hongKongDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        DateComponents(calendar: ICalendar.hongKong, timeZone: ICalendar.hongKong.timeZone,
                       year: year, month: month, day: day, hour: hour, minute: minute).date!
    }
}
