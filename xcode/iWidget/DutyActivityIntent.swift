import AppIntents
import Foundation

/// 捷徑動作「更新更份倒數」：讀今日同明日更份，啟動或者更新鎖定畫面／動態島嘅倒數。
/// 喺捷徑 App →「自動化」→「個人」揀幾個時間（例如返工前 3 小時、每 2 小時）執行，揀「立即執行」。
/// 倒數數字由系統自己跳，執行呢個動作係為咗將倒數對準下一件事。
struct UpdateDutyCountdownIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "更新更份倒數"
    static var description = IntentDescription("讀今日同明日嘅更份，開始或者更新鎖定畫面嘅下一件事倒數（返工、接車、落地、放工）。")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = await DutyActivityManager.refresh()
        return .result(dialog: "\(message)")
    }
}

/// 捷徑動作「結束更份倒數」。
struct EndDutyCountdownIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "結束更份倒數"
    static var description = IntentDescription("結束鎖定畫面嘅更份倒數。")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await DutyActivityManager.endAll()
        return .result(dialog: "已結束倒數。")
    }
}
