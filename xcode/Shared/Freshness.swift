import Foundation

/// 資料新鮮度：「最後**任一相關來源**成功取得」嘅時間，抽成純邏輯。
///
/// 呢檔只 import Foundation、唔碰快取同網絡，所以可以喺 `iWidgetTests` 直接測
/// （`ExtraInfo`／`OverviewEntry` 本身唔喺 test target，之前套邏輯物理上測唔到）。
/// `ExtraInfo`／`OverviewEntry` 只負責喺快取讀出各來源嘅成功時間，再 delegate 過嚟。
enum Freshness {

    /// 邊個 widget 範圍寫入／讀回天氣警告。
    ///
    /// 今日咭同「各項資訊」喺同一個 extension 入面共用同一份快取，而警告係兩個 widget 都會畫嘅
    /// **同一份資料**；如果成功時間都記喺同一個 key，今日咭就會顯示「各項資訊」啱啱成功嘅時間
    /// （反之亦然），即「互相灌水」。所以成功時間要分範圍記。
    /// 呢度自包含一個 enum，唔 reference `OverviewPart`（佢喺未入 test target 嘅檔）。
    enum Scope: String, CaseIterable {
        /// 今日咭
        case today
        /// 各項資訊
        case info
    }

    /// 升級前天氣警告只有一份共用快取，key 就係呢個；而家只讀唔寫（舊裝置容錯用）。
    static let legacyWarningsKey = "warnings"

    /// 分範圍嘅警告快取 key（資料同 `DataCache` 記嘅成功時間都會跟範圍分開）。
    static func warningsKey(_ scope: Scope) -> String { "warnings.\(scope.rawValue)" }

    /// 取清單入面最遲嘅成功時間；全部 nil（一個來源都冇成功記錄）就 nil，即「未有資料」。
    /// 「相關」由呼叫端決定：只把該口徑會畫嘅來源放進清單，唔相關嘅唔應該出現喺度。
    /// 傳入嘅必須係成功時間；用舊快取 fallback 時照傳舊時間，唔好傳本次時間，唔係就冒充啱啱更新。
    static func latest(_ successes: [Date?]) -> Date? { successes.compactMap { $0 }.max() }

    /// 本範圍有成功記錄就用佢；冇（例如由舊版本升上嚟、尚未成功讀過）先退返 fallback 嘅舊記錄。
    /// fallback 唔會翻新：得返舊快取時間時仍然係舊時間，唔會因為又試咗一次就變「啱啱更新」；兩邊都冇就 nil。
    static func stamp(current: Date?, fallback: Date?) -> Date? { current ?? fallback }

    /// `ExtraInfo` 各來源嘅成功時間（nil = 該來源從來冇成功記錄）。三個口徑用同一份資料，
    /// 所以「today 唔受 info 成功影響」呢類分範圍行為可以喺呢度直接測。
    /// 更份／學校日曆（只有今日咭畫）同 VPS（只有資訊畫）唔喺呢度，由 `OverviewEntry` 用 `latest` 補。
    struct Sources {
        /// 天氣預報（今日咭同「各項資訊」都畫）
        var weather: Date?
        /// 天氣警告：今日咭範圍（`warningsKey(.today)`）
        var warningsToday: Date?
        /// 天氣警告：各項資訊範圍（`warningsKey(.info)`）
        var warningsInfo: Date?
        /// 屯馬綫狀況（兩個都畫）
        var train: Date?
        /// 黃金
        var gold: Date?
        /// 空氣質素
        var air: Date?
        /// 匯率
        var fx: Date?
        /// 最新系統版本
        var latestOS: Date?

        /// 今日咭「更新於」：天氣、自己範圍嘅警告、屯馬綫（加更份／學校日曆，喺 `OverviewEntry` 補）。
        /// 唔計黃金／空氣／匯率／最新版本——呢啲由「各項資訊」更新，計入嚟就係灌水。
        var todayStamp: Date? { Freshness.latest([weather, warningsToday, train]) }

        /// 各項資訊「更新於」：天氣、自己範圍嘅警告、屯馬綫、黃金、空氣、匯率、最新版本（加 VPS，喺 `OverviewEntry` 補）。
        /// 唔計更份／學校日曆（呢啲由今日咭更新），亦唔計今日咭範圍嘅警告時間。
        var infoStamp: Date? { Freshness.latest([weather, warningsInfo, train, gold, air, fx, latestOS]) }

        /// 全 app 口徑（app 內預覽用）：全部來源都算，兩個範圍嘅警告時間都計；
        /// 語意同以前一樣係「任一來源成功」，唔分 widget。
        var overallStamp: Date? {
            Freshness.latest([weather, warningsToday, warningsInfo, train, gold, air, fx, latestOS])
        }
    }
}
