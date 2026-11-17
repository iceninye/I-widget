import XCTest

/// `TodayPlan`：今日咭位唔夠時「邊樣先讓位」嘅次序。
///
/// 用家回報：大格 widget（systemLarge）頂部有 05:31–13:01、天氣、7 日色條、本週概況、明日，
/// 底部剩低一大舊空白，而學校日程完全唔見（連「學校」標題都冇）。根因唔係學校資料讀唔到，
/// 而係 `ViewThatFits` 嘅候選把「成塊學校收起」擺咗喺第二格——即係最冇價值先讓位、最尾先收嘅
/// 反而係 7 日色條同逐時預報。呢邊就係驗緊呢個優先次序。
final class TodayPlanTests: XCTestCase {

    private func levels(_ maxSchoolRows: Int = 3) -> [TodayPlan.Level] {
        TodayPlan.levels(maxSchoolRows: maxSchoolRows)
    }

    /// `OverviewView` 入面逐格寫死 `TodayPlan.level(0..<levelCount)`，兩邊數量一定要夾到。
    func testLevelCountMatchesCandidates() {
        for rows in [-1, 0, 1, 3, 6, 10] {
            XCTAssertEqual(levels(rows).count, TodayPlan.levelCount, "maxSchoolRows = \(rows)")
        }
    }

    /// 第 0 格係「全部顯示」：位夠就要照出學校、7 日、本週、明日，同唔收今日咭次要行。
    func testFirstLevelShowsEverything() {
        let first = levels(3)[0]
        XCTAssertTrue(first.strip)
        XCTAssertTrue(first.week)
        XCTAssertTrue(first.tomorrow)
        XCTAssertTrue(first.holiday)
        XCTAssertFalse(first.compactCard, "最齊嗰格唔應該收今日咭嘅提示同逐時預報")
        XCTAssertEqual(first.schoolRows, 3)
    }

    /// 學校最尾先收：除咗最後一格，每一格都要有學校（哪怕淨低一行）。
    func testSchoolIsLastToGo() {
        for rows in [1, 3, 6, 10] {
            let all = levels(rows)
            for (index, level) in all.dropLast().enumerated() {
                XCTAssertGreaterThan(level.schoolRows, 0, "maxSchoolRows = \(rows)：第 \(index) 格唔應該成塊學校收起")
            }
            XCTAssertEqual(all.last?.schoolRows, 0, "最後一格先可以冇學校")
        }
    }

    /// 學校一行都未減之前，要先收過「本週概況」同今日咭嘅逐時預報（用家指明嘅優先次序）。
    func testWeekSummaryAndHourlyGiveWayBeforeSchool() {
        let all = levels(10)
        XCTAssertFalse(all[1].week, "第二格要先收本週概況")
        XCTAssertEqual(all[1].schoolRows, 10, "收本週概況唔應該順帶減學校行")
        XCTAssertTrue(all[2].compactCard, "第三格再收今日咭提示＋逐時預報")
        XCTAssertEqual(all[2].schoolRows, 10, "收逐時預報唔應該順帶減學校行")
    }

    /// 收咗 7 日色條、收咗明日嗰啲格，學校要仍然喺度（以前呢兩格學校已經唔見咗）。
    func testSchoolSurvivesStripAndTomorrowLoss() {
        let all = Array(levels(3).dropLast())
        XCTAssertTrue(
            all.contains { !$0.strip && !$0.week && $0.schoolRows > 0 },
            "收咗 7 日色條同本週概況之後，學校要仲喺度"
        )
        XCTAssertTrue(
            all.contains { !$0.tomorrow && $0.schoolRows > 0 },
            "收咗明日之後，學校要仲喺度"
        )
    }

    /// 逐級只收唔放：後一格唔可以比前一格多嘢，否則 `ViewThatFits` 揀錯格會溢出界。
    func testLevelsOnlyLoseContent() {
        for rows in [0, 3, 6, 10] {
            let all = levels(rows)
            for index in 1..<all.count {
                XCTAssertTrue(
                    TodayPlan.isSubset(all[index], of: all[index - 1]),
                    "maxSchoolRows = \(rows)：第 \(index) 格比上一格仲多嘢 \(all[index])"
                )
            }
        }
    }

    /// 學校行數只可以逐級減，中途唔可以升返上去（睇落會彈下彈下）。
    func testSchoolRowsMonotonic() {
        for rows in [1, 3, 6, 10] {
            let counts = levels(rows).map { $0.schoolRows }
            for index in 1..<counts.count {
                XCTAssertLessThanOrEqual(counts[index], counts[index - 1], "maxSchoolRows = \(rows)：\(counts)")
            }
        }
    }

    /// 唔止「3 行／冇」兩檔：特大 widget 要真會減到 3 行、再減到 1 行先至收塊。
    func testSchoolHasIntermediateRowCounts() {
        let counts = levels(10).map { $0.schoolRows }
        XCTAssertEqual(Array(counts.dropLast()), [10, 10, 10, 3, 3, 3, 3, 1], "學校逐級減行嘅台階")
    }

    /// 假期行（一個字）要排喺 7 日色條（最企位）之前讓位，而且收假期嗰格唔該順帶減學校行。
    func testHolidayGivesWayBeforeStrip() {
        let all = levels(10)
        guard let noHoliday = all.firstIndex(where: { !$0.holiday }),
              let noStrip = all.firstIndex(where: { !$0.strip }) else {
            return XCTFail("要有一格收假期、一格收 7 日色條")
        }
        XCTAssertLessThan(noHoliday, noStrip, "假期行應該比 7 日色條早讓位")
        XCTAssertEqual(all[noHoliday].schoolRows, all[noHoliday - 1].schoolRows)
    }

    /// `schoolRowBudget` 維持原本嘅 3／6／10 檔；systemLarge（可用高約 354pt）係 3 行。
    func testRowBudgetBuckets() {
        XCTAssertEqual(TodayPlan.schoolRowBudget(height: 354), 3, "systemLarge：3 行")
        XCTAssertEqual(TodayPlan.schoolRowBudget(height: 420), 3)
        XCTAssertEqual(TodayPlan.schoolRowBudget(height: 421), 6)
        XCTAssertEqual(TodayPlan.schoolRowBudget(height: 480), 6)
        XCTAssertEqual(TodayPlan.schoolRowBudget(height: 481), 10)
    }

    /// 大格 widget（systemLarge）個情境：裝唔落第 0 格之後，仲要有多過一條「有學校」嘅台階先至可以冇學校。
    func testLargeWidgetHasSchoolFallbacks() {
        let rows = TodayPlan.schoolRowBudget(height: 354)
        let withSchool = levels(rows).filter { $0.schoolRows > 0 }
        XCTAssertGreaterThanOrEqual(
            withSchool.count, TodayPlan.levelCount - 1,
            "以前第二格就完全冇學校，所以一裝唔落就變咗用家見到嘅空白"
        )
    }

    /// 高度異常（讀到 0 或者負數）都唔可以變成「學校得 0 行」而連標題都冇。
    func testWeirdBudgetStillShowsOneSchoolRow() {
        XCTAssertEqual(levels(0)[0].schoolRows, 1)
        XCTAssertEqual(levels(-2)[0].schoolRows, 1)
    }

    /// 越界 index 要回傳最接近嘅一格：extension 攞越界係 crash，即係成個 widget 空白。
    func testLevelAccessorClamps() {
        let all = levels(3)
        XCTAssertEqual(TodayPlan.level(-1, maxSchoolRows: 3), all[0])
        XCTAssertEqual(TodayPlan.level(0, maxSchoolRows: 3), all[0])
        XCTAssertEqual(TodayPlan.level(TodayPlan.levelCount - 1, maxSchoolRows: 3), all[all.count - 1])
        XCTAssertEqual(TodayPlan.level(99, maxSchoolRows: 3), all[all.count - 1])
    }
}
