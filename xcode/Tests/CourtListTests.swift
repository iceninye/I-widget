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
        XCTAssertEqual(day.upcoming(afterMinute: 539).map(\.caseNo), ["1", "2"])
        XCTAssertEqual(day.upcoming(afterMinute: 540).map(\.caseNo), ["2"])
        XCTAssertEqual(day.upcoming(afterMinute: 560).map(\.caseNo), ["2"])
        XCTAssertEqual(day.upcoming(afterMinute: 570).map(\.caseNo), ["2"])
        XCTAssertEqual(day.upcoming(afterMinute: 600).map(\.caseNo), ["2"])
        XCTAssertEqual(day.upcoming(afterMinute: 840), [])
        XCTAssertEqual(day.upcoming(afterMinute: 1439), [])
    }

    func testCatalogAllSelectionDoesNotDuplicateMagistrates() {
        XCTAssertEqual(CourtCatalog.all.count, 20)
        XCTAssertEqual(CourtCatalog.allCodes.count, 19)
        XCTAssertEqual(Set(CourtCatalog.allCodes).count, 19)
        XCTAssertFalse(CourtCatalog.allCodes.contains("ALLMAG"))
        XCTAssertTrue(CourtCatalog.magistrateCodes.isSubset(of: Set(CourtCatalog.allCodes)))
        XCTAssertEqual(CourtCatalog.selection([]), CourtCatalog.allCodes)
        XCTAssertEqual(CourtCatalog.selection(CourtCatalog.all.map(\.code)), CourtCatalog.allCodes)
        XCTAssertEqual(CourtCatalog.selection(["DC", "DC", "CFA", "invalid"]), ["DC", "CFA"])
        XCTAssertEqual(CourtCatalog.selection(["ALLMAG", "ETNMAG", "DC"]), ["ALLMAG", "DC"])
        XCTAssertEqual(CourtCatalog.selection(["ALLMAG"]), ["ALLMAG"])
    }

    func testFullDocumentAndFileCacheKeepMoreThan300Records() throws {
        let date = try XCTUnwrap(CourtList.date(fromISO: "2026-10-26"))
        let html = rows([["法庭", "法官", "時間", "案件編號", "訴訟各方"]] + (1...651).map {
            ["第 1 庭", "陳 法官", "09:30", "DCCJ \($0)/2026", "不應儲存的訴訟人"]
        })
        let parsed = CourtList.parse(html)
        XCTAssertEqual(parsed.count, 651)
        let day = try CourtList.document(html, code: "DC", day: date, fetchedAt: date)
        XCTAssertEqual(day.total, 651)
        XCTAssertEqual(day.cases.count, 651)
        XCTAssertEqual(day.cases.last?.caseNo, "DCCJ 651/2026")
        XCTAssertNil(day.metadata.publishedAt)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try CourtFileCache.save(day, directory: directory)
        XCTAssertEqual(CourtFileCache.load(code: "DC", dateCode: "26102026", directory: directory), day)
        XCTAssertNil(CourtFileCache.load(code: "DC", dateCode: "27102026", directory: directory))
        XCTAssertNil(CourtFileCache.load(code: "CFA", dateCode: "26102026", directory: directory))
        XCTAssertNil(CourtFileCache.load(code: "../DC", dateCode: "26102026", directory: directory))
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(day), as: UTF8.self).contains("不應儲存的訴訟人"))
        let summary = CourtSummary(day: day, at: date, listDate: date)
        XCTAssertEqual(summary.rows.count, 2)
        XCTAssertEqual(summary.total, 651)
        var truncated = day
        truncated.cases = Array(day.cases.prefix(300))
        XCTAssertThrowsError(try CourtFileCache.save(truncated, directory: directory))
    }

    func testEmptyMalformedAndAttachmentOnlyPagesAreNotNoHearings() throws {
        let date = try XCTUnwrap(CourtList.date(fromISO: "2026-10-26"))
        for html in ["", "<html></html>", "<html>Service unavailable</html>",
                     "<table><tr><td>案件編號</td></tr></table>", "<p>沒有案件表", "沒有案件表",
                     "<html><a href='list.pdf'>見附頁</a></html>",
                     "<script>沒有案件表</script>",
                     "<p>若沒有案件表，請明天再查閱。</p>"] {
            XCTAssertThrowsError(try CourtList.document(html, code: "DC", day: date, fetchedAt: date))
        }
        let noList = try CourtList.document("<html><p>此日期並無案件表。</p></html>", code: "DC", day: date, fetchedAt: date)
        XCTAssertEqual(noList.metadata.source, .officialNoList)
        XCTAssertFalse(noList.error)
        XCTAssertEqual(noList.total, 0)
        let parsed = try CourtList.document(fixture, code: "DC", day: date, fetchedAt: date)
        XCTAssertEqual(parsed.metadata.source, .parsed)
    }

    func testFailedRefreshPreservesTimestampAndMarksStale() throws {
        let date = try XCTUnwrap(CourtList.date(fromISO: "2026-10-26"))
        let day = try CourtList.document(fixture, code: "DC", day: date, fetchedAt: date)
        XCTAssertFalse(day.metadata.isStale(at: date.addingTimeInterval(599)))
        XCTAssertTrue(day.metadata.isStale(at: date.addingTimeInterval(600)))
        XCTAssertTrue(day.metadata.isStale(at: date.addingTimeInterval(-1)))
        let failed = CourtList.failed(day, message: "連線失敗", at: date.addingTimeInterval(700))
        XCTAssertTrue(failed.error)
        XCTAssertEqual(failed.cases, day.cases)
        XCTAssertEqual(failed.metadata.fetchedAt, date)
        XCTAssertEqual(failed.metadata.attemptedAt, date.addingTimeInterval(700))
        XCTAssertEqual(failed.metadata.failure, "連線失敗")
        XCTAssertEqual(failed.metadata.label(total: failed.total, error: failed.error, at: date), "更新失敗・舊資料")
    }

    func testDocumentRejectsExplicitWrongScheduleDate() throws {
        let date = try XCTUnwrap(CourtList.date(fromISO: "2026-10-27"))
        XCTAssertThrowsError(try CourtList.document("<p>案件表日期：26/10/2026</p>" + fixture, code: "DC", day: date, fetchedAt: date))
        XCTAssertNoThrow(try CourtList.document("<p>案件表日期：27/10/2026</p>" + fixture, code: "DC", day: date, fetchedAt: date))
    }

    func testMergedCaseNumbersDoNotKeepParticipantNotes() {
        XCTAssertEqual(CourtList.trimCaseNo("DCCJ 1/2026 DCCJ 2/2026 張某 對 李某"), "DCCJ 1/2026 DCCJ 2/2026")
        XCTAssertEqual(CourtList.parse(rows([["時間", "案件編號", "訴訟各方"], ["09:30", "張某 123", "李某"]])), [])
    }

    func testPagingWrapsAndVisitsEveryCourt() {
        let codes = CourtCatalog.allCodes
        let count = CourtPaging.pageCount(for: codes.count)
        XCTAssertEqual(count, 7)
        let visited = (0..<count).flatMap { CourtPaging.indices(page: $0, courtCount: codes.count).map { codes[$0] } }
        XCTAssertEqual(visited, codes)
        XCTAssertEqual(CourtPaging.indices(page: 6, courtCount: 19).count, 1)
        XCTAssertEqual(CourtPaging.normalized(-1, count: count), 6)
        XCTAssertEqual(CourtPaging.normalized(7, count: count), 0)
        XCTAssertEqual(CourtPaging.pageCount(for: 0), 1)
        XCTAssertTrue(CourtPaging.indices(page: 0, courtCount: 0).isEmpty)
        XCTAssertEqual(CourtPaging.configurationKey(codes: [], autoRotate: true), CourtPaging.configurationKey(codes: CourtCatalog.allCodes, autoRotate: true))
        XCTAssertNotEqual(CourtPaging.configurationKey(codes: ["DC"], autoRotate: true), CourtPaging.configurationKey(codes: ["CFA"], autoRotate: true))
        XCTAssertNotEqual(CourtPaging.configurationKey(codes: ["DC"], autoRotate: true), CourtPaging.configurationKey(codes: ["DC"], autoRotate: false))
    }

    func testPageRotationAnchorsManualSelection() throws {
        let date = try XCTUnwrap(CourtList.date(fromISO: "2026-10-26"))
        let state = CourtPageState(page: 6, anchoredAt: date)
        XCTAssertEqual(state.page(at: date.addingTimeInterval(599), count: 7, autoRotate: true), 6)
        XCTAssertEqual(state.page(at: date.addingTimeInterval(600), count: 7, autoRotate: true), 0)
        XCTAssertEqual(state.page(at: date.addingTimeInterval(1200), count: 7, autoRotate: true), 1)
        XCTAssertEqual(state.page(at: date.addingTimeInterval(1200), count: 7, autoRotate: false), 6)
        let dates = CourtPaging.dates(now: date.addingTimeInterval(500), state: state, autoRotate: true)
        XCTAssertEqual(dates[1], date.addingTimeInterval(600))
    }

    func testDateAndTimelineEveningBoundary() throws {
        let date = try XCTUnwrap(CourtList.date(fromISO: "2026-10-26"))
        let before = date.addingTimeInterval(18 * 3600 + 29 * 60 + 59)
        let boundary = before.addingTimeInterval(1)
        XCTAssertEqual(CourtList.dateCode(CourtList.listDate(now: before)), "26102026")
        XCTAssertEqual(CourtList.dateCode(CourtList.listDate(now: boundary)), "27102026")
        XCTAssertEqual(CourtList.minuteOfDay(now: before, listDate: date), 1109)
        XCTAssertNil(CourtList.minuteOfDay(now: boundary, listDate: CourtList.listDate(now: boundary)))
        let dates = CourtPaging.dates(now: before, state: CourtPageState(anchoredAt: before), autoRotate: true)
        XCTAssertTrue(dates.contains(boundary))
        XCTAssertTrue(dates.filter { $0 >= boundary }.allSatisfy { CourtList.dateCode(CourtList.listDate(now: $0)) == "27102026" })
        XCTAssertEqual(CourtList.isoDate(date), "2026-10-26")
        XCTAssertNil(CourtList.date(fromISO: "2026-02-30"))
        XCTAssertNil(CourtList.date(fromISO: "2026-2-01"))
        XCTAssertNil(CourtList.date(fromISO: "../../other"))
    }

    func testUpcomingMidnightAndStableTies() {
        let day = CourtDay(code: "DC", dateCode: "26102026", total: 4, cases: [
            CourtCase(room: "A", judge: "", minutes: 0, caseNo: "1"),
            CourtCase(room: "A", judge: "", minutes: 1, caseNo: "2"),
            CourtCase(room: "A", judge: "", minutes: 1, caseNo: "3"),
            CourtCase(room: "A", judge: "", minutes: 1439, caseNo: "4"),
        ])
        XCTAssertEqual(day.upcoming(afterMinute: 0).map(\.caseNo), ["2", "3", "4"])
        XCTAssertEqual(day.upcoming(afterMinute: 1).map(\.caseNo), ["4"])
        XCTAssertTrue(day.upcoming(afterMinute: 1439).isEmpty)
    }

    private func unloaded(_ codes: [String]) -> [CourtDay] {
        codes.map { CourtDay(code: $0, dateCode: "26102026", total: 0, cases: [], error: true,
                             metadata: CourtMetadata(source: .unavailable)) }
    }

    func testLoadOrderUsesMissingThenOldestSuccessAndCountsFailedAttempts() {
        let date = Date(timeIntervalSince1970: 1000)
        var saved = unloaded(["CFA", "DC", "CRC", "SMT", "HCMC", "LT"])
        saved[0].metadata.fetchedAt = date.addingTimeInterval(100)
        saved[1].metadata.fetchedAt = date.addingTimeInterval(10)
        saved[3].metadata.attemptedAt = date.addingTimeInterval(200)
        saved[5].metadata.fetchedAt = date.addingTimeInterval(20)
        saved[5].metadata.attemptedAt = date.addingTimeInterval(300)
        let order = CourtList.loadOrder(cached: saved)
        XCTAssertEqual(order.map { saved[$0].code }, ["CRC", "HCMC", "DC", "CFA", "SMT", "LT"])
        XCTAssertEqual(CourtList.loadOrder(cached: []), [])
    }

    func testVisiblePriorityReservesBackgroundSlotAndRepeatedFailuresVisitAllCourts() {
        var saved = unloaded(CourtCatalog.allCodes)
        let visible = CourtPaging.indices(page: 5, courtCount: saved.count).map { saved[$0].code }
        let order = CourtList.loadOrder(cached: saved, visibleCodes: visible + visible + ["invalid"])
        XCTAssertEqual(Array(order.prefix(3)), [15, 16, 0])
        XCTAssertEqual(Set(order), Set(saved.indices))
        XCTAssertEqual(order.count, saved.count)
        var visited = Set<String>()
        // 最壞情況：每次只有三個請求開始，全部逾時。固定可見頁亦唔會餓死其餘法院。
        for round in 1...saved.count {
            for index in CourtList.loadOrder(cached: saved, visibleCodes: visible).prefix(3) {
                visited.insert(saved[index].code)
                saved[index] = CourtList.failed(saved[index], message: "逾時", at: Date(timeIntervalSince1970: Double(round)))
            }
        }
        XCTAssertEqual(visited, Set(CourtCatalog.allCodes))
    }

    func testFirstFailedAttemptPersistsWithoutInventingSuccessfulFetch() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let missing = unloaded(["DC", "CFA"])
        XCTAssertThrowsError(try CourtFileCache.save(missing[0], directory: directory))
        let failed = CourtList.failed(missing[0], message: "更新已取消", at: Date(timeIntervalSince1970: 1000))
        try CourtFileCache.save(failed, directory: directory)
        let restored = try XCTUnwrap(CourtFileCache.load(code: "DC", dateCode: "26102026", directory: directory))
        XCTAssertEqual(restored, failed)
        XCTAssertNil(restored.metadata.fetchedAt)
        XCTAssertEqual(restored.metadata.source, .unavailable)
        XCTAssertTrue(restored.metadata.isStale(at: Date()))
        XCTAssertEqual(CourtList.loadOrder(cached: [restored, missing[1]]), [1, 0])
        var invalid = restored
        invalid.error = false
        XCTAssertThrowsError(try CourtFileCache.save(invalid, directory: directory))
    }

    private actor LoadProbe {
        var started: [String] = []
        var cancelled: [String] = []
        var delivered: [CourtDay] = []
        var active = 0
        var peak = 0
        private var startWaiter: CheckedContinuation<Void, Never>?

        func waitUntilStarted() async {
            if !started.isEmpty { return }
            await withCheckedContinuation { startWaiter = $0 }
        }

        func load(_ saved: CourtDay, delay: Duration) async -> CourtDay {
            started.append(saved.code)
            active += 1
            peak = max(peak, active)
            startWaiter?.resume()
            startWaiter = nil
            defer { active -= 1 }
            do {
                try await Task.sleep(for: delay)
                var result = saved
                result.error = false
                result.metadata = CourtMetadata(source: .officialNoList, fetchedAt: Date(), attemptedAt: Date())
                return result
            } catch {
                cancelled.append(saved.code)
                return CourtList.failed(saved, message: "更新已取消", at: Date())
            }
        }

        func record(_ day: CourtDay) { delivered.append(day) }
        func snapshot() -> (started: [String], cancelled: [String], delivered: [CourtDay], peak: Int, active: Int) {
            (started, cancelled, delivered, peak, active)
        }
    }

    func testLoadAllKeepsSelectionOrderAndProgressWithoutWaitingForDeadline() async {
        let saved = unloaded(["DC", "CFA", "LT", "SMT", "CRC"])
        let probe = LoadProbe()
        let clock = ContinuousClock()
        let start = clock.now
        let results = await CourtList.loadAll(cached: saved, now: Date(), timeout: 3, visibleCodes: ["CRC"],
                                              onLoaded: { await probe.record($0) }) { code in
            await probe.load(saved.first { $0.code == code }!, delay: code == "CRC" ? .milliseconds(5) : .milliseconds(40))
        }
        XCTAssertLessThan(start.duration(to: clock.now), .seconds(1.5))
        XCTAssertEqual(results.map(\.code), saved.map(\.code))
        XCTAssertTrue(results.allSatisfy { !$0.error })
        let state = await probe.snapshot()
        XCTAssertEqual(Set(state.started.prefix(3)), Set(["CRC", "DC", "CFA"]))
        XCTAssertEqual(Set(state.delivered.map(\.code)), Set(saved.map(\.code)))
        XCTAssertEqual(state.delivered.count, saved.count)
        XCTAssertTrue(state.cancelled.isEmpty)
        XCTAssertEqual(state.peak, 3)
        XCTAssertEqual(state.active, 0)
    }

    func testDeadlineCancelsInflightLoadsAndKeepsCompletedResults() async {
        let stale = CourtDay(code: "CRC", dateCode: "26102026", total: 1,
                             cases: [CourtCase(room: "第 1 庭", judge: "", minutes: 600, caseNo: "CCDI 1/2026")],
                             metadata: CourtMetadata(fetchedAt: Date(timeIntervalSince1970: 1000)))
        let saved = unloaded(["DC", "CFA", "LT", "SMT"]) + [stale]
        let probe = LoadProbe()
        let clock = ContinuousClock()
        let start = clock.now
        let results = await CourtList.loadAll(cached: saved, now: Date(), timeout: 0.15,
                                              onLoaded: { await probe.record($0) }) { code in
            await probe.load(saved.first { $0.code == code }!, delay: code == "DC" ? .zero : .seconds(5))
        }
        XCTAssertLessThan(start.duration(to: clock.now), .seconds(1.5))
        XCTAssertEqual(results.map(\.code), saved.map(\.code))
        XCTAssertFalse(results[0].error)
        XCTAssertTrue(results.dropFirst().allSatisfy(\.error))
        XCTAssertEqual(results.last?.cases, stale.cases)
        XCTAssertEqual(results.last?.metadata.fetchedAt, stale.metadata.fetchedAt)
        let state = await probe.snapshot()
        XCTAssertEqual(Set(state.started), Set(["DC", "CFA", "LT", "SMT"]))
        XCTAssertEqual(Set(state.cancelled), Set(["CFA", "LT", "SMT"]))
        XCTAssertEqual(state.delivered, [results[0]])
        XCTAssertEqual(state.peak, 3)
        XCTAssertEqual(state.active, 0)
    }

    func testDeadlineAlsoCancelsWhileProgressCallbackIsSuspended() async {
        let saved = unloaded(["DC", "CFA", "LT", "SMT"])
        let probe = LoadProbe()
        let clock = ContinuousClock()
        let start = clock.now
        let results = await CourtList.loadAll(cached: saved, now: Date(), timeout: 0.15, onLoaded: { result in
            await probe.record(result)
            try? await Task.sleep(for: .seconds(5))
        }) { code in
            await probe.load(saved.first { $0.code == code }!, delay: code == "DC" ? .zero : .seconds(5))
        }
        XCTAssertLessThan(start.duration(to: clock.now), .seconds(1.5))
        XCTAssertFalse(results[0].error)
        let state = await probe.snapshot()
        XCTAssertEqual(Set(state.started), Set(["DC", "CFA", "LT"]))
        XCTAssertEqual(Set(state.cancelled), Set(["CFA", "LT"]))
        XCTAssertEqual(state.delivered, [results[0]])
        XCTAssertEqual(state.active, 0)
    }

    func testZeroDeadlineDoesNotStartLoads() async {
        let saved = unloaded(["DC", "CFA"])
        let probe = LoadProbe()
        let results = await CourtList.loadAll(cached: saved, now: Date(), timeout: 0) { code in
            await probe.load(saved.first { $0.code == code }!, delay: .zero)
        }
        let state = await probe.snapshot()
        XCTAssertTrue(state.started.isEmpty)
        XCTAssertEqual(results.map(\.code), saved.map(\.code))
        XCTAssertTrue(results.allSatisfy(\.error))
    }

    func testParentCancellationStopsLoadsWithoutStartingTheRest() async {
        let saved = unloaded(["DC", "CFA", "LT", "SMT"])
        let probe = LoadProbe()
        let task = Task {
            await CourtList.loadAll(cached: saved, now: Date(), onLoaded: { await probe.record($0) }) { code in
                await probe.load(saved.first { $0.code == code }!, delay: .seconds(5))
            }
        }
        await probe.waitUntilStarted()
        task.cancel()
        let results = await task.value
        let state = await probe.snapshot()
        XCTAssertLessThanOrEqual(state.started.count, 3)
        XCTAssertEqual(Set(state.cancelled), Set(state.started))
        XCTAssertTrue(state.delivered.isEmpty)
        XCTAssertEqual(state.active, 0)
        XCTAssertTrue(results.allSatisfy(\.error))
    }

    func testURL() {
        XCTAssertEqual(CourtList.url(code: "CFA", dateCode: "26102026")?.absoluteString,
                       "https://e-services.judiciary.hk/dcl/view.jsp?lang=tc&date=26102026&court=CFA")
    }
}
