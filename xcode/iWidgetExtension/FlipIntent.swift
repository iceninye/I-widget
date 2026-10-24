import AppIntents
import WidgetKit

extension FlipState {
    static func load() -> FlipState {
        DataCache.load(FlipState.self, key: "flips") ?? FlipState()
    }

    func save() {
        DataCache.save(self, key: "flips")
    }
}

/// 撳資料格：反轉（或者轉返）嗰格，再叫 widget 刷新。
/// 記低反轉時間，等 provider 用快取即刻畫，唔使重新上網。
struct FlipIntent: AppIntent {
    static var title: LocalizedStringResource = "反轉資料格"

    @Parameter(title: "格")
    var tile: String

    init() {}

    init(tile: String) {
        self.tile = tile
    }

    func perform() async throws -> some IntentResult {
        var state = FlipState.load()
        state.toggle(tile, now: Date())
        state.save()
        DataCache.save(Date(), key: "flipAt")
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
