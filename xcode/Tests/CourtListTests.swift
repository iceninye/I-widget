import XCTest

final class CourtListTests: XCTestCase {
    private let fixture = """
    <html><body><table>
    <tr><td><p>法庭</p></td><td><p>法官</p></td><td><p>時間</p></td><td><p>案件編號</p></td><td><p>訴訟各方</p></td><td><p>性質</p></td></tr>
    <tr><td><p>Court</p></td><td><p>Judge</p></td><td><p>Time</p></td><td><p>Case No.</p></td><td><p>Parties</p></td><td><p>Nature</p></td></tr>
    <tr><td rowspan="2"><p><span>第 3 </span><span>庭</span></p></td><td rowspan="2"><p>陳&nbsp;法官</p></td><td><p>9:30 am</p></td><td><p>DCCJ&nbsp;1/2026</p></td><td><p>甲 對 乙</p></td><td><p>聆訊</p></td></tr>
    <tr><td><p>2:15 pm</p></td><td><p>DCCJ 2/2026</p></td><td><p>丙 對 丁</p></td><td><p>聆訊</p></td></tr>
    <tr><td><p>第 5 庭</p></td><td><p>李 法官</p></td><td><p>下午3時30分</p></td><td><p>DCCC 7/2026</p></td><td><p>&#x7532;</p></td><td></td></tr>
    </table></body></html>
    """

    func testParseMapsColumnsAndFillsDown() {
        let cases = CourtList.parse(fixture)
        XCTAssertEqual(cases.count, 3)
        XCTAssertEqual(cases[0], CourtCase(room: "第 3 庭", judge: "陳 法官", minutes: 570, caseNo: "DCCJ 1/2026"))
        // rowspan 令第二行少咗前兩格：沿用上一行嘅法庭同法官
        XCTAssertEqual(cases[1], CourtCase(room: "第 3 庭", judge: "陳 法官", minutes: 14 * 60 + 15, caseNo: "DCCJ 2/2026"))
        XCTAssertEqual(cases[2].minutes, 15 * 60 + 30)
        XCTAssertEqual(cases[2].room, "第 5 庭")
    }

    func testParseWithoutTableIsEmpty() {
        XCTAssertEqual(CourtList.parse("<html>找不到案件表</html>"), [])
    }

    func testTimeParsing() {
        XCTAssertEqual(CourtList.parseTime("9:30 am"), 570)
        XCTAssertEqual(CourtList.parseTime("12:05 PM"), 12 * 60 + 5)
        XCTAssertEqual(CourtList.parseTime("12:05 am"), 5)
        XCTAssertEqual(CourtList.parseTime("09:30"), 570)
        XCTAssertEqual(CourtList.parseTime("下午2:30"), 14 * 60 + 30)
        XCTAssertEqual(CourtList.parseTime("10時15分"), 615)
        XCTAssertNil(CourtList.parseTime("全日"))
        XCTAssertNil(CourtList.parseTime("12"))
    }

    func testEntityDecoding() {
        XCTAssertEqual(CourtList.cleanText("<p>A&amp;B&nbsp;&#x7532;&#20057;</p>"), "A&B 甲乙")
    }

    func testListDateSkipsWeekendAndEvening() {
        let calendar = ICalendar.hongKong
        func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
            calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
        }
        // 2026-10-26 係星期一
        XCTAssertEqual(CourtList.dateCode(CourtList.listDate(now: date(2026, 10, 26, 9, 0))), "26102026")
        XCTAssertEqual(CourtList.dateCode(CourtList.listDate(now: date(2026, 10, 26, 18, 30))), "27102026")
        // 星期五夜晚同週末都睇星期一
        XCTAssertEqual(CourtList.dateCode(CourtList.listDate(now: date(2026, 10, 30, 19, 0))), "02112026")
        XCTAssertEqual(CourtList.dateCode(CourtList.listDate(now: date(2026, 10, 31, 10, 0))), "02112026")
    }

    func testUpcomingSortsAndFiltersPast() {
        let day = CourtDay(code: "DC", dateCode: "26102026", total: 3, cases: [
            CourtCase(room: "B", judge: "", minutes: 840, caseNo: "2"),
            CourtCase(room: "A", judge: "", minutes: 540, caseNo: "1"),
            CourtCase(room: "C", judge: "", minutes: nil, caseNo: "3"),
        ])
        XCTAssertEqual(day.upcoming(afterMinute: nil).map(\.caseNo), ["1", "2", "3"])
        XCTAssertEqual(day.upcoming(afterMinute: 600).map(\.caseNo), ["2"])
        XCTAssertEqual(day.upcoming(afterMinute: 550).map(\.caseNo), ["1", "2"])
    }

    func testURL() {
        XCTAssertEqual(CourtList.url(code: "CFA", dateCode: "26102026")?.absoluteString,
                       "https://e-services.judiciary.hk/dcl/view.jsp?lang=tc&date=26102026&court=CFA")
    }
}
