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

    private func rows(_ rows: [[String]]) -> String {
        "<table>" + rows.map { "<tr>" + $0.map { "<td><p>\($0)</p></td>" }.joined() + "</tr>" }.joined() + "</table>"
    }

    func testParseMagistrateBannersAndBatchRows() {
        let html = rows([
            ["法庭 Court :", "第 1 庭 Court No.1"],
            ["裁判官 Magistrate :", "陳大文 裁判官"],
            ["9:30 am", "TWS 1/2026", "某被告", "襲警", "答辯"],
            ["", "TWS 2/2026", "另一被告", "盜竊", "訊問"],
            ["", "傳票", "交通部", "12 件案件 Case(s)"],
            ["法庭 Court :", "第 2 庭 Court No.2"],
            ["10:00 am", "KCCC 5/2026", "被告", "傷人", "審訊"],
        ])
        let cases = CourtList.parse(html)
        XCTAssertEqual(cases.map(\.caseNo), ["TWS 1/2026", "TWS 2/2026", "KCCC 5/2026"])
        XCTAssertEqual(cases[0].room, "第 1 庭")
        XCTAssertEqual(cases[0].judge, "陳大文 裁判官")
        // 時間只喺同一組第一行出現，後續行沿用；換庭後重新計
        XCTAssertEqual(cases[1].minutes, 570)
        XCTAssertEqual(cases[2].room, "第 2 庭")
        XCTAssertEqual(cases[2].minutes, 600)
    }

    func testParseLabourTribunalHeaderCaseNumber() {
        let html = rows([
            ["時間", "申索编號", "申索人", "被申索人"],
            ["第 2 庭 Court No.2"],
            ["審裁官 Presiding Officer :", "王小明 審裁官"],
            ["9:30 am", "LBTC 100/2026", "甲", "乙"],
            ["10:00 am", "LBTC 101/2026", "丙", "丁"],
        ])
        let cases = CourtList.parse(html)
        XCTAssertEqual(cases.count, 2)
        XCTAssertEqual(cases[1].caseNo, "LBTC 101/2026")
        XCTAssertEqual(cases[1].room, "第 2 庭")
        XCTAssertEqual(cases[1].judge, "王小明 審裁官")
        XCTAssertEqual(cases[1].minutes, 600)
    }

    func testTrimCaseNoDropsTrailingNoteButKeepsMergedCases() {
        XCTAssertEqual(CourtList.trimCaseNo("CCDI-269/2022(MC) [5/7]# 沒有陪審員"), "CCDI-269/2022(MC) [5/7]#")
        XCTAssertEqual(CourtList.trimCaseNo("DCCJ 1/2026"), "DCCJ 1/2026")
        XCTAssertEqual(CourtList.trimCaseNo("DCCJ 1/2026 DCCJ 2/2026"), "DCCJ 1/2026 DCCJ 2/2026")
    }

    func testChinesePartCutsEnglishTail() {
        XCTAssertEqual(CourtList.chinesePart("第 5 庭 2 字樓 Court No.5 (2/F)"), "第 5 庭 2 字樓")
        XCTAssertEqual(CourtList.chinesePart("第 5 庭"), "第 5 庭")
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
        XCTAssertEqual(day.upcoming(afterMinute: 600).map(\.caseNo), ["2", "3"])
        XCTAssertEqual(day.upcoming(afterMinute: 570).map(\.caseNo), ["2", "3"])
        XCTAssertEqual(day.upcoming(afterMinute: 560).map(\.caseNo), ["1", "2", "3"])
    }

    func testURL() {
        XCTAssertEqual(CourtList.url(code: "CFA", dateCode: "26102026")?.absoluteString,
                       "https://e-services.judiciary.hk/dcl/view.jsp?lang=tc&date=26102026&court=CFA")
    }

    func testListDateSkipsPublicHolidays() {
        let calendar = ICalendar.hongKong
        let monday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 9))!
        // 星期一同星期二都係假期 → 星期三
        let holidays: Set<String> = ["20261026", "20261027"]
        XCTAssertEqual(CourtList.dateCode(CourtList.listDate(now: monday, holidays: holidays)), "28102026")
    }

    func testPublicHolidaysParse() {
        let json = #"{"vcalendar":[{"vevent":[{"dtstart":["20261225",{"value":"DATE"}],"summary":"聖誕節"},{"dtstart":["20261226",{"value":"DATE"}]},{"summary":"x"}]}]}"#
        XCTAssertEqual(PublicHolidays.parse(Data(json.utf8)), ["20261225", "20261226"])
        XCTAssertEqual(PublicHolidays.parse(Data("oops".utf8)), [])
    }

    func testJudgeCellIgnoresRemarks() {
        let html = """
        <table><tr><td>法庭</td><td>時間</td><td>案件編號</td><td>備註</td></tr>
        <tr><td>第1庭</td><td>9:30</td><td>DCCC 1/2026</td><td>案件由法官另行處理，押後至下星期</td></tr></table>
        """
        XCTAssertEqual(CourtList.parse(html).first?.judge, "")
    }

    func testDecodeFallsBackToBig5() {
        XCTAssertEqual(CourtList.decode(Data("法庭".utf8)), "法庭")
        let big5 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.big5_HKSCS_1999.rawValue)))
        XCTAssertEqual(CourtList.decode("法庭".data(using: big5)!), "法庭")
    }
}
