import XCTest

final class RosterTests: XCTestCase {
    /// 虛構 roster：3 行輪換 ＋ 1 行全 TBC（唔參與輪換）。
    private var roster: Roster {
        Roster(
            rows: [
                ["1101101", "1101102", "RD", "1101104", "1101105", "6091101", "RD"],
                ["AL", "AL", "AL", "SH", "SH", "RD", "RD"],
                ["RD", "RD", "7091101", "1101201", "1101202", "RD", "7091102"],
                Array(repeating: "TBC", count: 7),
            ],
            numbers: [1, 2, 3, 4],
            anchorRow: 2,
            anchorMonday: "2026-10-19",
            overrides: [:]
        )
    }

    private func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    func testDayMath() {
        XCTAssertEqual(Days.number("1970-01-01"), 0)
        XCTAssertEqual(Days.weekdayIndex("2026-10-23"), 4)
        XCTAssertEqual(Days.mondayOf("2026-10-23"), "2026-10-19")
        XCTAssertEqual(Days.mondayOf("2026-10-25"), "2026-10-19")
        XCTAssertEqual(Days.add("2026-10-31", 1), "2026-11-01")
        XCTAssertNil(Days.number("not-a-date"))
    }

    func testServiceDateChangesAtFourAmHongKong() {
        XCTAssertEqual(Days.serviceDate(date("2026-10-23T18:00:00Z")), "2026-10-23")
        XCTAssertEqual(Days.serviceDate(date("2026-10-23T19:59:00Z")), "2026-10-23")
        XCTAssertEqual(Days.serviceDate(date("2026-10-23T20:00:00Z")), "2026-10-24")
    }

    func testRowAfterSkipsPendingRows() {
        XCTAssertEqual(roster.rowAfter(2, weeks: 0), 2)
        XCTAssertEqual(roster.rowAfter(2, weeks: 1), 3)
        XCTAssertEqual(roster.rowAfter(2, weeks: 2), 1)
        XCTAssertEqual(roster.rowAfter(2, weeks: 3), 2)
        XCTAssertEqual(roster.rowAfter(2, weeks: -1), 1)
        XCTAssertEqual(roster.rowAfter(4, weeks: 5), 4)
        XCTAssertNil(roster.rowAfter(99, weeks: 1))
    }

    func testEntryFollowsCycle() {
        XCTAssertEqual(roster.entry(on: "2026-10-23")?.code, "SH")
        XCTAssertEqual(roster.entry(on: "2026-10-23")?.row, 2)
        XCTAssertEqual(roster.entry(on: "2026-10-28")?.code, "7091101")
        XCTAssertEqual(roster.entry(on: "2026-11-02")?.code, "1101101")
    }

    func testOverrideWins() {
        var changed = roster
        changed.overrides["2026-10-23"] = "8022131"
        let entry = changed.entry(on: "2026-10-23")
        XCTAssertEqual(entry?.code, "8022131")
        XCTAssertEqual(entry?.isOverride, true)
    }

    func testUnknownAnchorGivesNoEntry() {
        var broken = roster
        broken.anchorRow = 99
        XCTAssertNil(broken.entry(on: "2026-10-23"))
    }

    func testParseAPIIgnoresNames() throws {
        let json = """
        {"ok":true,"record":{"schema":1,"title":"x",
         "rows":[["RD","RD","RD","RD","RD","RD","RD"]],"numbers":[7],"names":["Someone"],
         "anchor":{"row":7,"monday":"2026-10-19"},"overrides":{"2026-10-24":"8022101"},"version":3}}
        """
        let parsed = try RosterAPI.parse(Data(json.utf8))
        XCTAssertEqual(parsed.numbers, [7])
        XCTAssertEqual(parsed.anchorRow, 7)
        XCTAssertEqual(parsed.overrides["2026-10-24"], "8022101")
    }

    func testParseAPIRejectsBadShape() {
        let short = #"{"record":{"rows":[["RD","RD"]],"numbers":[1],"anchor":{"row":1,"monday":"2026-10-19"}}}"#
        XCTAssertThrowsError(try RosterAPI.parse(Data(short.utf8)))
        let noAnchor = #"{"record":{"rows":[["RD","RD","RD","RD","RD","RD","RD"]],"numbers":[1]}}"#
        XCTAssertThrowsError(try RosterAPI.parse(Data(noAnchor.utf8)))
        XCTAssertThrowsError(try RosterAPI.parse(Data("{}".utf8)))
    }

    func testTokenValidation() {
        let token = String(repeating: "a1", count: 16)
        XCTAssertEqual(RosterAPI.cleanToken(" \(token)\n"), token)
        XCTAssertNil(RosterAPI.cleanToken("short"))
        XCTAssertNil(RosterAPI.cleanToken(token.uppercased()))
        XCTAssertNil(RosterAPI.cleanToken(nil))
        XCTAssertEqual(RosterAPI.url(token: token)?.absoluteString, RosterAPI.base + token)
        XCTAssertNil(RosterAPI.url(token: "bad token"))
    }

    func testShiftClass() {
        XCTAssertEqual(ShiftClass.of(on: 6 * 3_600, off: 15 * 3_600), .dawn)
        XCTAssertEqual(ShiftClass.of(on: Int(6.5 * 3_600), off: 15 * 3_600), .early)
        XCTAssertEqual(ShiftClass.of(on: 10 * 3_600, off: 18 * 3_600), .mid)
        XCTAssertEqual(ShiftClass.of(on: 15 * 3_600, off: 23 * 3_600), .late)
        XCTAssertEqual(ShiftClass.of(on: 14 * 3_600, off: 86_400 + 1_801), .night)
        XCTAssertEqual(ShiftClass.of(on: 14 * 3_600, off: 86_400 + 1_800), .mid)
    }

    func testDutyBasicParseSkipsEntriesWithoutTimes() throws {
        let json = #"{"duties":{"1100101":[17100,"屯門",42300,"錦上路",6.5,"DE"],"SEP":[null,null,null,null,0,""]}}"#
        let duties = try DutyBasic.parse(Data(json.utf8))
        XCTAssertEqual(duties.count, 1)
        XCTAssertEqual(duties["1100101"]?.on, 17_100)
        XCTAssertEqual(duties["1100101"]?.offPlace, "錦上路")
        XCTAssertThrowsError(try DutyBasic.parse(Data("{}".utf8)))
    }

    func testSummary() {
        var plain = roster
        plain.overrides["2026-10-23"] = "1100101"
        plain.overrides["2026-10-24"] = "7091999"
        let duties = ["1100101": DutyTime(on: 17_100, onPlace: "屯門", off: 42_300, offPlace: "錦上路", hours: 6.5)]

        let duty = RosterSummary.summary(roster: plain, duties: duties, date: "2026-10-23")
        XCTAssertEqual(duty?.label, "死早更 1100101")
        XCTAssertEqual(duty?.times, "04:45–11:45")
        XCTAssertEqual(duty?.places, "屯門 → 錦上路")

        let unknown = RosterSummary.summary(roster: plain, duties: duties, date: "2026-10-24")
        XCTAssertEqual(unknown?.label, "更份 7091999")
        XCTAssertNil(unknown?.times)

        let rest = RosterSummary.summary(roster: roster, duties: duties, date: "2026-10-24")
        XCTAssertEqual(rest?.label, "休息")

        XCTAssertEqual(RosterSummary.clock(90_000), "01:00+1")
        XCTAssertNil(RosterSummary.summary(roster: roster, duties: [:], date: "garbage"))
    }
}
