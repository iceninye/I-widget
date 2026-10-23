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

    private let sheets = [
        DutySheet(code: "1101", file: "DS1101.json", special: false, dates: []),
        DutySheet(code: "7091", file: "DS7091.json", special: false, dates: []),
        DutySheet(code: "7091M", file: "DS7091M.json", special: true, dates: ["2026-11-01"]),
        DutySheet(code: "8022", file: "DS8022.json", special: true, dates: ["2026-10-24"]),
    ]

    func testDutyDayFromBasic() {
        var plain = roster
        plain.overrides["2026-10-23"] = "1100101"
        plain.overrides["2026-10-25"] = "7091999"
        let basic = ["1100101": DutyTime(on: 17_100, onPlace: "屯門", off: 42_300, offPlace: "錦上路", hours: 6.5)]
        let make = { (date: String) in
            DutyDay.make(roster: plain, date: date, basic: basic, cards: [:], sheets: self.sheets, places: .empty)
        }

        let duty = make("2026-10-23")
        XCTAssertEqual(duty?.title, "死早更 1100101")
        XCTAssertEqual(duty?.times, "04:45 – 11:45")
        XCTAssertEqual(duty?.route, "屯門 → 錦上路")
        XCTAssertEqual(duty?.hoursText, "6.5 小時")
        XCTAssertEqual(duty?.isOverride, true)

        let unknown = make("2026-10-25")
        XCTAssertEqual(unknown?.title, "更份 7091999")
        XCTAssertNil(unknown?.times)

        let rest = DutyDay.make(roster: roster, date: "2026-10-24", basic: basic, cards: [:], sheets: sheets, places: .empty)
        XCTAssertEqual(rest?.title, "休息")
        XCTAssertEqual(rest?.kind, .rest)

        XCTAssertNil(DutyDay.make(roster: roster, date: "garbage", basic: [:], cards: [:], sheets: [], places: .empty))
    }

    func testDutyDayFromCardUsesDatedSheetAndMeal() throws {
        var plain = roster
        plain.overrides["2026-11-01"] = "7091101"
        plain.overrides["2026-10-24"] = "6091124"
        let json = #"{"duties":[{"id":"7091101","group":"KSR","on":[31980,"KSR"],"off":[90000,"TAD"],"work":510,"meal":[38640,40440,"LT2","HUH3"]},{"id":"7091102","on":null}]}"#
        let cards = try DutyData.parseCards(Data(json.utf8), ids: ["7091101", "7091102"])
        XCTAssertEqual(cards.count, 1)
        let keyed = [DutyDay.cardKey(sheet: "7091M", id: "7091101"): cards["7091101"]!]
        let places = PlaceNames(stations: ["KSR": "錦上路", "HUH": "紅磡"], places: [:])

        let day = DutyDay.make(roster: plain, date: "2026-11-01", basic: [:], cards: keyed, sheets: sheets, places: places)
        XCTAssertEqual(day?.datedSheet, "7091M")
        XCTAssertEqual(day?.group, "KSR")
        XCTAssertEqual(day?.shift, .night)
        XCTAssertEqual(day?.times, "08:53 – 01:00")
        XCTAssertEqual(day?.route, "錦上路 → 大圍廠 TAD")
        XCTAssertEqual(day?.hoursText, "8.5 小時")
        XCTAssertEqual(day?.mealText, "用膳 10:44–11:14 紅磡廠 LT2 → 紅磡 3")
        XCTAssertNil(day?.hint)

        // 8022 唔係 6091 開頭：唔自動換，只提示
        let special = DutyDay.make(roster: plain, date: "2026-10-24", basic: [:], cards: [:], sheets: sheets, places: places)
        XCTAssertNil(special?.datedSheet)
        XCTAssertEqual(special?.hint, "當日用 Duty Sheet 8022，更份可能係 8022124")
    }

    func testServiceSecondDates() {
        let day = DutyDay(date: "2026-10-23", code: "X", kind: .duty, title: "X")
        XCTAssertEqual(day.moment(atServiceSecond: 0), date("2026-10-22T16:00:00Z"))
        XCTAssertEqual(day.moment(atServiceSecond: 90_000), date("2026-10-23T17:00:00Z"))
    }

    func testIndexAndPlaceNames() throws {
        let index = #"{"sheets":[{"code":"7091M","file":"DS7091M.json","class":"special","dates":["2026-11-01"],"alsoOn":["2026-11-02"]},{"code":"bad","file":"../x.json"}]}"#
        let parsed = try DutyData.parseIndex(Data(index.utf8))
        XCTAssertEqual(parsed, [DutySheet(code: "7091M", file: "DS7091M.json", special: true, dates: ["2026-11-01", "2026-11-02"])])
        XCTAssertEqual(DutyData.sheet(for: "7091101", date: "2026-11-02", sheets: parsed), "7091M")
        XCTAssertEqual(DutyData.sheet(for: "7091101", date: "2026-11-03", sheets: parsed), "7091")

        let network = #"{"stations":{"KSR":{"tc":"錦上路"}},"places":{"note":"x","OS":{"tc":"外放車"}}}"#
        let places = try PlaceNames.parse(Data(network.utf8))
        XCTAssertEqual(places.name("KSR2"), "錦上路 2")
        XCTAssertEqual(places.name("KSR"), "錦上路")
        XCTAssertEqual(places.name("OS"), "外放車")
        XCTAssertEqual(places.name("ZZZ"), "ZZZ")
    }
}
