import XCTest

/// `WarningLayout`：警告 badge 嘅 budget／揀邊幾條。「至少留一條」「嚴重優先」「+N 計數」
/// 呢啲規則抽咗出 Shared 之後先測得到（之前的 `pickedWarnings` 係 widget target 內嘅 private func）。
/// 寬度仍然係估算，未喺真機量過，所以呢邊只驗「關係同不變量」，唔驗實際像素。
final class WarningLayoutTests: XCTestCase {
    private func warning(_ text: String, severe: Bool = false) -> WeatherWarning {
        WeatherWarning(text: text, severe: severe)
    }

    /// budget 負數（行已經比圖標＋屯馬綫撐滿）都要留一條，唔可以成行空白睇唔到警告。
    func testNegativeBudgetStillShowsOne() {
        let warnings = [warning("黑色暴雨", severe: true), warning("雷暴"), warning("黃色暴雨")]
        let layout = WarningLayout.layout(warnings, limit: 2, width: -500)
        XCTAssertEqual(layout.shown.count, 1, "budget 幾細都要顯示最嚴重嗰條")
        XCTAssertEqual(layout.shown.first?.text, "黑色暴雨")
        XCTAssertEqual(layout.overflow, 2)
    }

    /// 用真實 budget 計出嘅負數：細格＋屯馬綫＋「+N 項」之位。
    func testRealisticNarrowRowKeepsOneWarning() {
        let budget = WarningLayout.budget(.small, train: "屯馬綫 延誤", reserveOverflow: true)
        XCTAssertLessThan(budget, 0, "呢個組合本來就放唔落第二條")
        let layout = WarningLayout.layout([warning("雷暴"), warning("三號風球")], limit: 1, width: budget)
        XCTAssertEqual(layout.shown.map { $0.text }, ["雷暴"])
        XCTAssertEqual(layout.overflow, 1)
    }

    /// 嚴重優先：後面嘅紅色暴雨唔可以俾前面嘅非嚴重警告企住位。
    func testSevereWarningsComeFirst() {
        let layout = WarningLayout.layout(
            [warning("雷暴"), warning("黑色暴雨", severe: true), warning("黃色暴雨")],
            limit: 1, width: 0
        )
        XCTAssertEqual(layout.shown, [warning("黑色暴雨", severe: true)])
        XCTAssertEqual(layout.overflow, 2)
    }

    /// 同組保持原本次序（唔好因為排序改咗天文台畀嘅順序）。
    func testOrderWithinGroupKept() {
        let layout = WarningLayout.layout(
            [warning("甲", severe: true), warning("乙", severe: true), warning("丙"), warning("丁")],
            limit: 4, width: 10_000
        )
        XCTAssertEqual(layout.shown.map { $0.text }, ["甲", "乙", "丙", "丁"])
    }

    /// +N 計數正確：顯示 + 收起 = 總數；唔論 budget 幾細都成立。
    func testOverflowCounts() {
        let warnings = [warning("甲"), warning("乙"), warning("丙")]
        // 第一條永遠留低；第二條啱好放唔落
        let width = WarningLayout.badgeWidth("甲") + WarningLayout.badgeWidth("乙") - 1
        let layout = WarningLayout.layout(warnings, limit: 3, width: width)
        XCTAssertEqual(layout.shown.count, 1)
        XCTAssertEqual(layout.overflow, 2)
        XCTAssertEqual(layout.shown.count + layout.overflow, warnings.count)

        let capped = WarningLayout.layout(warnings, limit: 2, width: 10_000)
        XCTAssertEqual(capped.shown.count, 2, "位夠都要受 limit 限制")
        XCTAssertEqual(capped.overflow, 1)

        let nothing = WarningLayout.layout([], limit: 3, width: 10_000)
        XCTAssertEqual(nothing.shown.count, 0)
        XCTAssertEqual(nothing.overflow, 0, "冇警告唔好造出「+0 項」")
    }

    func testBudgetSubtractsTrainAndOverflowReserves() {
        let plain = WarningLayout.budget(.medium)
        let withTrain = WarningLayout.budget(.medium, train: "屯馬綫 延誤")
        let withBoth = WarningLayout.budget(.medium, train: "屯馬綫 延誤", reserveOverflow: true)
        XCTAssertGreaterThan(plain, 0)
        XCTAssertLessThan(withTrain, plain)
        XCTAssertLessThan(withBoth, withTrain)
        XCTAssertEqual(plain - withBoth, WarningLayout.badgeWidth("屯馬綫 延誤") + WarningLayout.overflowWidth, accuracy: 0.001)
    }

    /// 各 family 估值合理：large／extraLarge／extraLargePortrait 都要明顯闊過 medium，
    /// 唔可以再當同 medium 等闊（以前 budget 過早收埋變「+N 項」就係呢度嚟），
    /// extraLargePortrait 亦唔可以跌落 iPad 大格嗰檔。數值仍屬估算。
    func testWidthEstimatesAreOrdered() {
        for size in WarningLayout.Size.allCases {
            XCTAssertGreaterThan(WarningLayout.rowWidth(size), 0, "每個尺寸都要有正闊，唔可以靠 default 得零")
        }
        XCTAssertLessThan(WarningLayout.rowWidth(.small), WarningLayout.rowWidth(.medium))
        XCTAssertEqual(WarningLayout.rowWidth(.large), WarningLayout.rowWidth(.medium) * 2)
        XCTAssertGreaterThan(WarningLayout.rowWidth(.extraLarge), WarningLayout.rowWidth(.medium))
        XCTAssertGreaterThan(WarningLayout.rowWidth(.extraLargePortrait), WarningLayout.rowWidth(.medium))
        XCTAssertNotEqual(WarningLayout.rowWidth(.extraLargePortrait), WarningLayout.rowWidth(.wide))
        XCTAssertGreaterThan(WarningLayout.rowWidth(.wide), WarningLayout.rowWidth(.large))
        // medium 已經可以放兩條短警告：唔該唔好一開波就收埋第二條
        let budget = WarningLayout.budget(.medium)
        XCTAssertEqual(WarningLayout.layout([warning("黃色暴雨"), warning("雷暴")], limit: 2, width: budget).shown.count, 2)
    }

    func testTextWidthEstimateTreatsCJKAndASCII() {
        XCTAssertEqual(WarningLayout.text("雨", size: 10), 10)
        XCTAssertEqual(WarningLayout.text("A", size: 10), 5.5, accuracy: 0.001)
        XCTAssertEqual(WarningLayout.text("雨A", size: 10), 15.5, accuracy: 0.001)
        XCTAssertEqual(WarningLayout.badgeWidth("雨"), 25, "文字 10pt＋左右 padding 5+5＋spacing 5")
    }
}
