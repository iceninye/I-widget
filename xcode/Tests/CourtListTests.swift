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
        XCTAssertEqual(cases[0], CourtCase(room: "第 3 庭", judge: "陳 法官", minutes: 570, caseNo: "DCCJ 1/2026", nature: "聆訊"))
        // rowspan 令第二行少咗前兩格：沿用上一行嘅法庭同法官
        XCTAssertEqual(cases[1], CourtCase(room: "第 3 庭", judge: "陳 法官", minutes: 14 * 60 + 15, caseNo: "DCCJ 2/2026", nature: "聆訊"))
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

    func testNatureFromColumnOrStageWords() {
        let cases = CourtList.parse(fixture)
        // 第一行按「性質」欄；第二行合併格對唔到位，但「聆訊」係固定字眼；第三行冇
        XCTAssertEqual(cases.map(\.nature), ["聆訊", "聆訊", nil])
    }

    func testMagistrateStageWordsButNeverPartiesOrCharges() {
        let html = rows([
            ["法庭 Court :", "第 1 庭 Court No.1"],
            ["9:30 am", "TWS 1/2026", "陳大文", "襲警", "答辯 Plea"],
            ["", "TWS 2/2026", "李小明", "盜竊", "訊問"],
            ["10:00 am", "KCCC 5/2026", "張三", "傷人"],
        ])
        let cases = CourtList.parse(html)
        XCTAssertEqual(cases.map(\.nature), ["答辯", "訊問", nil])
        let leaked: Set<String> = ["陳大文", "李小明", "張三", "襲警", "盜竊", "傷人"]
        for item in cases {
            let fields: Set<String> = [item.nature ?? "", item.judge, item.room]
            XCTAssertTrue(fields.isDisjoint(with: leaked), "\(fields)")
        }
    }

    func testChargeColumnKeptInFull() {
        let long = String(repeating: "販運危險藥物；", count: 3) + "管有危險藥物"
        let html = rows([
            ["法庭", "法官", "時間", "案件編號", "訴訟各方", "性質/控罪", "應訊代表"],
            ["第 1 庭", "陳 法官", "9:30 am", "DCCC 1/2026", "香港特別行政區 訴 甲", "傷人 Wounding", "控方"],
            ["", "", "10:00 am", "DCCC 2/2026", "香港特別行政區 訴 乙", "\(long)", "控方"],
            ["", "", "11:00 am", "DCCC 3/2026", "香港特別行政區 訴 丙", "審訊 Trial", "控方"],
            ["", "", "12:00 pm", "DCCC 4/2026", "香港特別行政區 訴 丁", "", "控方"],
        ])
        let cases = CourtList.parse(html)
        XCTAssertEqual(cases.count, 4)
        XCTAssertEqual(cases[0].charge, "傷人")
        XCTAssertEqual(cases[0].detailText, "刑事案件")
        XCTAssertEqual(cases[1].charge, long)
        XCTAssertEqual(cases[2].stage, "審訊")
        XCTAssertNil(cases[2].charge)
        XCTAssertEqual(cases[2].detailText, "刑事案件 · 審訊")
        XCTAssertNil(cases[3].nature)
        XCTAssertNil(cases[3].charge)
    }

    func testVeryLongChargeIsTruncated() {
        let html = rows([
            ["法庭", "法官", "時間", "案件編號", "訴訟各方", "性質", "應訊代表"],
            ["第 1 庭", "陳 法官", "9:30 am", "DCCC 1/2026", "甲", String(repeating: "控", count: 300), "控方"],
        ])
        let charge = CourtList.parse(html).first?.charge
        XCTAssertEqual(charge?.count, CourtList.natureLimit + 1)
        XCTAssertTrue(charge?.hasSuffix("…") == true)
    }

    func testNatureEqualToPartiesIsDropped() {
        let html = rows([
            ["法庭", "法官", "時間", "案件編號", "訴訟各方", "性質", "應訊代表"],
            ["第 1 庭", "陳 法官", "9:30 am", "DCCC 1/2026", "香港特別行政區 訴 甲", "香港特別行政區 訴 甲", "控方"],
        ])
        let item = CourtList.parse(html).first
        XCTAssertNil(item?.nature)
        XCTAssertNil(item?.charge)
    }

    func testCaseTypeFromPrefix() {
        XCTAssertEqual(CaseTypes.prefix(of: "DCCJ 1/2026"), "DCCJ")
        XCTAssertEqual(CaseTypes.prefix(of: "CCDI-269/2022(MC)"), "CCDI")
        XCTAssertEqual(CaseTypes.classify("DCCJ 1/2026"), CaseType(category: .civil, label: "民事訴訟"))
        XCTAssertEqual(CaseTypes.classify("HCCC 12/2026").category, .criminal)
        XCTAssertEqual(CaseTypes.classify("FACV 3/2026").category, .appeal)
        XCTAssertEqual(CaseTypes.classify("HCMA 100/2026"), CaseType(category: .appeal, label: "裁判法院上訴"))
        XCTAssertEqual(CaseTypes.classify("FCMC 9/2026").category, .family)
        XCTAssertEqual(CaseTypes.classify("LBTC 100/2026").category, .tribunal)
        XCTAssertEqual(CaseTypes.classify("CCDI-269/2022(MC)").category, .inquest)
        // 裁判法院：法院代號 + CC／S
        XCTAssertEqual(CaseTypes.classify("KCCC 5/2026"), CaseType(category: .criminal, label: "刑事案件"))
        XCTAssertEqual(CaseTypes.classify("TWS 1/2026"), CaseType(category: .criminal, label: "傳票案件"))
        // 已知法院但唔認得嘅類型唔亂估；完全唔認得就「其他」
        XCTAssertEqual(CaseTypes.classify("LDXX 1/2026").category, .tribunal)
        XCTAssertEqual(CaseTypes.classify("HCZZ 1/2026"), CaseType(category: .other, label: "高院案件"))
        XCTAssertEqual(CaseTypes.classify("1/2026").category, .other)
    }

    func testDetailTextAndCategoryCounts() {
        XCTAssertEqual(CourtCase(room: "", judge: "", minutes: nil, caseNo: "DCCJ 1/2026", nature: "聆訊").detailText, "民事訴訟 · 聆訊")
        XCTAssertEqual(CourtCase(room: "", judge: "", minutes: nil, caseNo: "DCCJ 1/2026").detailText, "民事訴訟")
        let day = CourtDay(code: "DC", dateCode: "", total: 4, cases: [
            CourtCase(room: "", judge: "", minutes: nil, caseNo: "DCCJ 1/2026"),
            CourtCase(room: "", judge: "", minutes: nil, caseNo: "DCCC 1/2026"),
            CourtCase(room: "", judge: "", minutes: nil, caseNo: "DCCC 2/2026"),
            CourtCase(room: "", judge: "", minutes: nil, caseNo: "DCPI 1/2026"),
        ])
        XCTAssertEqual(day.categoryCounts, [
            CategoryCount(category: .criminal, count: 2),
            CategoryCount(category: .civil, count: 2),
        ])
    }

    func testStatusAroundStartTime() {
        let hearing = CourtCase(room: "A", judge: "", minutes: 600, caseNo: "1")
        XCTAssertEqual(hearing.status(atMinute: nil), .scheduled)
        XCTAssertEqual(hearing.status(atMinute: 599), .upcoming)
        XCTAssertEqual(hearing.status(atMinute: 600), .ongoing)
        XCTAssertEqual(hearing.status(atMinute: 619), .ongoing)
        XCTAssertEqual(hearing.status(atMinute: 620), .finished)
        XCTAssertEqual(CourtCase(room: "A", judge: "", minutes: nil, caseNo: "1").status(atMinute: 700), .scheduled)
    }

    func testLinkRoundTripAndMatch() {
        let link = CourtLink(code: "DC", caseNo: "DCCJ 1/2026", minutes: 570)
        XCTAssertEqual(CourtLink(url: link.url), link)
        XCTAssertEqual(CourtLink(url: CourtLink(code: "CFA").url), CourtLink(code: "CFA"))
        XCTAssertNil(CourtLink(url: URL(string: "https://example.com/court?code=DC")!))
        XCTAssertNil(CourtLink(url: URL(string: "iwidget://court")!))

        let day = CourtDay(code: "DC", dateCode: "26102026", total: 2, cases: [
            CourtCase(room: "A", judge: "", minutes: 570, caseNo: "DCCJ 1/2026"),
            CourtCase(room: "B", judge: "", minutes: 840, caseNo: "DCCJ 1/2026"),
        ])
        XCTAssertEqual(link.match(in: day)?.room, "A")
        XCTAssertEqual(CourtLink(code: "DC", caseNo: "DCCJ 1/2026", minutes: 840).match(in: day)?.room, "B")
        XCTAssertEqual(CourtLink(code: "DC", caseNo: "DCCJ 1/2026", minutes: 1).match(in: day)?.room, "A")
        XCTAssertNil(CourtLink(code: "DC").match(in: day))
    }

    func testAllocateRowsSharesLeftover() {
        XCTAssertEqual(CourtLayout.allocate(counts: [], budget: 10), [])
        XCTAssertEqual(CourtLayout.allocate(counts: [50, 50], budget: 10), [5, 5])
        // 一個只有 2 行，餘額畀另一個
        XCTAssertEqual(CourtLayout.allocate(counts: [2, 50], budget: 10), [2, 8])
        // 冇嘢睇嘅法院都保留 1 行（標題），預算唔夠也不少於 1
        XCTAssertEqual(CourtLayout.allocate(counts: [0, 0, 0], budget: 2), [1, 1, 1])
        XCTAssertEqual(CourtLayout.allocate(counts: [3, 3], budget: 100), [3, 3])
    }
}
