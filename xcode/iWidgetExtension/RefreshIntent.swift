import AppIntents
import WidgetKit

/// 「即時更新」掣：叫 WidgetKit 即刻重新讀取。系統仍可能因預算延遲，所以唔係秒級保證。
struct RefreshIntent: AppIntent {
    static var title: LocalizedStringResource = "即時更新"
    static var description = IntentDescription("即時重新讀取 widget 資料。")

    func perform() async throws -> some IntentResult {
        // 即時更新要真係上網，唔好當成剛剛反轉格嗰次
        DataCache.save(Date.distantPast, key: "flipAt")
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
