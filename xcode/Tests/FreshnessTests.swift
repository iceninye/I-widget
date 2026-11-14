import XCTest

/// `Freshness`：「最後任一相關來源成功」嘅時間。分範圍、fallback 唔翻新呢啲規則抽出嚟之後
/// 先測得到（`ExtraInfo`／`OverviewEntry` 本身唔喺 test target）。
final class FreshnessTests: XCTestCase {
    private let old = Date(timeIntervalSince1970: 1_700_000_000)
    private let newer = Date(timeIntervalSince1970: 1_700_003_600)

    /// 全部來源都冇成功記錄 → nil（顯示「未有資料」，唔係「啱啱更新」）。
    func testNoRecordIsNil() {
        XCTAssertNil(Freshness.latest([]))
        XCTAssertNil(Freshness.latest([nil, nil, nil]))
        XCTAssertNil(Freshness.Sources().todayStamp)
        XCTAssertNil(Freshness.Sources().infoStamp)
        XCTAssertNil(Freshness.Sources().overallStamp)
    }

    func testLatestPicksNewestSuccess() {
        XCTAssertEqual(Freshness.latest([old, nil, newer]), newer)
        XCTAssertEqual(Freshness.latest([newer, old]), newer)
    }

    /// 只用相關來源：黃金／空氣／匯率／最新版本唔係今日咭畫嘅資料，唔可以出現喺今日咭口徑。
    func testTodayUsesOnlyRelevantSources() {
        let sources = Freshness.Sources(gold: newer, air: newer, fx: newer, latestOS: newer)
        XCTAssertNil(sources.todayStamp, "資訊 widget 啱啱成功唔可以令今日咭顯示已更新")
        XCTAssertEqual(sources.infoStamp, newer)
        XCTAssertEqual(sources.overallStamp, newer, "全 app 口徑先係「任何來源」")
    }

    /// 今日咭範圍嘅警告成功時間唔應該去灌「各項資訊」嘅口徑。
    func testInfoDoesNotUseTodayWarningScope() {
        let sources = Freshness.Sources(warningsToday: newer)
        XCTAssertEqual(sources.todayStamp, newer)
        XCTAssertNil(sources.infoStamp, "今日咭範圍嘅警告成功時間唔應該灌水「各項資訊」")
        XCTAssertEqual(sources.overallStamp, newer)
    }

    /// 核心：一方成功唔可以令另一方睇落似啱啱更新（之前兩條 provider 路徑寫同一 key 就係呢度出事）。
    func testWarningScopesDoNotInflateEachOther() {
        var both = Freshness.Sources()
        both.warningsToday = old
        both.warningsInfo = newer
        XCTAssertEqual(both.todayStamp, old, "今日咭只讀 today 嗰份：仍然係自己上次成功嘅舊時間")
        XCTAssertEqual(both.infoStamp, newer)

        var reverse = Freshness.Sources()
        reverse.warningsToday = newer
        reverse.warningsInfo = old
        XCTAssertEqual(reverse.todayStamp, newer)
        XCTAssertEqual(reverse.infoStamp, old, "資訊只讀 info 嗰份：唔受今日咭成功影響")
    }

    /// fallback 唔翻新：本次冇成功記錄就照用舊時間，唔會變成「啱啱更新」；兩邊都冇就 nil。
    func testFallbackKeepsOlderTime() {
        XCTAssertEqual(Freshness.stamp(current: nil, fallback: old), old)
        XCTAssertEqual(Freshness.stamp(current: newer, fallback: old), newer)
        XCTAssertNil(Freshness.stamp(current: nil, fallback: nil))
        // 得返舊快取時間時，聚合出嚟嘅口徑都唔會翻新
        XCTAssertEqual(Freshness.Sources(warningsToday: Freshness.stamp(current: nil, fallback: old)).todayStamp, old)
    }

    /// 舊裝置容錯：分範圍 key 同升級前共用 key 要唔同（讀嗰時新 key 冇記錄就 fallback 舊 key）。
    func testScopeKeysAreSeparateButLegacyReadable() {
        XCTAssertEqual(Freshness.warningsKey(.today), "warnings.today")
        XCTAssertEqual(Freshness.warningsKey(.info), "warnings.info")
        XCTAssertEqual(Freshness.legacyWarningsKey, "warnings")
        XCTAssertNotEqual(Freshness.warningsKey(.today), Freshness.warningsKey(.info))
        XCTAssertNotEqual(Freshness.warningsKey(.today), Freshness.legacyWarningsKey)
        XCTAssertNotEqual(Freshness.warningsKey(.info), Freshness.legacyWarningsKey)
        XCTAssertEqual(Set(Freshness.Scope.allCases), [Freshness.Scope.today, .info])
    }
}
