import AppIntents
import WidgetKit

extension WidgetTheme {
    static func load() -> WidgetTheme {
        DataCache.load(WidgetTheme.self, key: "theme") ?? .classic
    }

    func save() {
        DataCache.save(self, key: "theme")
    }
}

/// 右上角調色掣：轉去下一個風格。用快取即刻畫，唔使等上網。
struct ThemeIntent: AppIntent {
    static var title: LocalizedStringResource = "轉換風格"

    func perform() async throws -> some IntentResult {
        WidgetTheme.load().next.save()
        DataCache.save(Date(), key: "flipAt")
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
