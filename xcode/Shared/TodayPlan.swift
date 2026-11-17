import Foundation

/// 今日咭（大／特大）位唔夠時「邊樣嘢先讓位」嘅順序，同埋學校日程留幾多行。
///
/// 抽咗出 `Shared` 先測得到：`OverviewView` 嗰邊係 SwiftUI／WidgetKit，單元測試 target 入面冇。
/// 之前順序寫死喺 `ViewThatFits` 嘅候選度，第二格就成塊學校收起，而 7 日色條、本週概況、
/// 今日咭嘅逐時預報反而一路保留 —— 結果大格 widget（systemLarge）底部剩低一大舊空白，學校日程完全唔見
/// （用家回報：05:31–13:01、天氣、7 日、本週概況、明日都喺度，冇「學校」甚至冇區塊標題）。
/// 呢度將優先次序講清楚：**學校日程係最尾先收嘅一樣**，收佢之前要先收過本週概況、
/// 更份提示＋逐時預報、假期行、7 日色條同明日；學校自己內部亦先減行，唔使「全有或全無」。
enum TodayPlan {

    /// 一格候選版面：得邊幾塊。`schoolRows == 0` 即成個學校區塊收起。
    struct Level: Equatable {
        /// 未來 7 日色條
        var strip: Bool
        /// 「本週 ⋯」概況一行
        var week: Bool
        /// 明日更份一行
        var tomorrow: Bool
        /// 學校日程列幾多項（0 = 收起）
        var schoolRows: Int
        /// 學校區塊底下面嘅假期一行（活動本身照留）
        var holiday: Bool
        /// 今日咭收次要行：提示、返工／放工逐時預報（字級唔變）
        var compactCard: Bool
    }

    /// 候選數量。`OverviewView` 入面嘅 `ViewThatFits` 要寫死相同數量嘅 `stack(_:)`：
    /// `ForEach` 擺入 `ViewThatFits` 只會當一個子視圖，逐級收起就唔會發生。
    /// 上限：`ViewThatFits` 只處理頭 10 個子視圖，呢個數唔可以超過 10。
    static let levelCount = 9

    /// 學校最多可以列幾多行：跟 widget 可用高度分檔（維持原本嘅 3／6／10 檔）。
    static func schoolRowBudget(height: CGFloat) -> Int {
        height > 480 ? 10 : (height > 420 ? 6 : 3)
    }

    /// 由最齊（第 0 格）到最精簡（最後一格）。後面每一格都只係「比上一格少嘅嘢」，
    /// 所以 `ViewThatFits` 揀到邊格都唔會溢出界。
    static func levels(maxSchoolRows: Int) -> [Level] {
        let full = max(1, maxSchoolRows)
        let some = min(3, full)
        let one = min(1, full)
        return [
            // 0 全部
            Level(strip: true, week: true, tomorrow: true, schoolRows: full, holiday: true, compactCard: false),
            // 1 先收「本週概況」（一行文字，學校一行都冇減）
            Level(strip: true, week: false, tomorrow: true, schoolRows: full, holiday: true, compactCard: false),
            // 2 再收今日咭嘅提示同返工／放工逐時預報（字級唔變）
            Level(strip: true, week: false, tomorrow: true, schoolRows: full, holiday: true, compactCard: true),
            // 3 學校減到 `some` 行，照樣有「另有 N 項」（`maxSchoolRows <= 3` 呢級用唔著，
            // 第 3 格會同第 2 格一樣：多重複量一次候選而已，唔影響揀邊格）
            Level(strip: true, week: false, tomorrow: true, schoolRows: some, holiday: true, compactCard: true),
            // 4 收假期一行（學校活動本身留低）
            Level(strip: true, week: false, tomorrow: true, schoolRows: some, holiday: false, compactCard: true),
            // 5 先收 7 日色條（佢最企位，但次序排喺學校之後）
            Level(strip: false, week: false, tomorrow: true, schoolRows: some, holiday: false, compactCard: true),
            // 6 收明日（今日更份已經喺大字度講咗）
            Level(strip: false, week: false, tomorrow: false, schoolRows: some, holiday: false, compactCard: true),
            // 7 學校淨低一行——再細都仲見到「學校」同冇活動時嘅說明
            Level(strip: false, week: false, tomorrow: false, schoolRows: one, holiday: false, compactCard: true),
            // 8 真係裝唔落（systemMedium 呢類）先成塊學校收起
            Level(strip: false, week: false, tomorrow: false, schoolRows: 0, holiday: false, compactCard: true)
        ]
    }

    /// 第 `index` 格。越界會回傳最接近嘅一格，唔會 crash（呼叫端寫死 `0..<levelCount`）。
    static func level(_ index: Int, maxSchoolRows: Int) -> Level {
        let all = levels(maxSchoolRows: maxSchoolRows)
        if index < 0 { return all[0] }
        guard index < all.count else { return all[all.count - 1] }
        return all[index]
    }

    /// 兩格比較：`later` 係咪唔比 `earlier` 多嘢（用嚟驗「逐級只收唔放」）。
    static func isSubset(_ later: Level, of earlier: Level) -> Bool {
        if later.strip, !earlier.strip { return false }
        if later.week, !earlier.week { return false }
        if later.tomorrow, !earlier.tomorrow { return false }
        if later.holiday, !earlier.holiday { return false }
        if !later.compactCard, earlier.compactCard { return false }
        return later.schoolRows <= earlier.schoolRows
    }
}
