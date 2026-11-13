import AppIntents
import Foundation

/// 捷徑動作「排交接提示」：讀今日同明日更份，排好每次接車、落地嘅通知。
/// 喺捷徑 App →「自動化」→「個人」揀每日一個時間（例如 03:30）執行，揀「立即執行」就唔使確認，
/// 唔使開 app。
struct ScheduleHandoverAlertsIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "排交接提示"
    static var description = IntentDescription("讀今日同明日嘅更份，排好返工、每次接車、落地同用膳後接車嘅通知。")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let token = AppSettings.string(AppSettings.rosterToken)
        guard RosterAPI.cleanToken(token) != nil else {
            return .result(dialog: "未填 tml-roster token：開 i-widget →「設定」填一次。")
        }
        guard await HandoverNotifier.isAuthorized() else {
            return .result(dialog: "未允許通知：開 i-widget →「設定」→「交接提示」開啟。")
        }
        UserDefaults.standard.set(true, forKey: HandoverNotifier.enabledKey)
        let now = Date()
        let data = await ScheduleData.load(token: token, now: now)
        let settings = HandoverSettings.load()
        let alerts = data.handoverAlerts(now: now, settings: settings)
        let count = await HandoverNotifier.schedule(alerts, settings: settings, now: now)
        // 有開更份倒數就順手更新（排提示同倒數用同一份資料）
        var countdown = ""
        if DutyActivityManager.isEnabled {
            countdown = "\n" + (await DutyActivityManager.sync(events: data.dutyEvents(now: now), now: now))
        }
        if count == 0 {
            return .result(dialog: "今日同明日冇提示（休息，或者已經放工）。\(countdown)")
        }
        let first = alerts.first.map { "，第一個 \(Self.clock($0.fireAt))" } ?? ""
        return .result(dialog: "已排好 \(count) 個交接提示\(first)。\(countdown)")
    }

    private static func clock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hant_HK")
        formatter.timeZone = TimeZone(identifier: "Asia/Hong_Kong")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter.string(from: date)
    }
}

struct IWidgetShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ScheduleHandoverAlertsIntent(),
            phrases: ["用 \(.applicationName) 排交接提示", "\(.applicationName) 交接提示"],
            shortTitle: "排交接提示",
            systemImageName: "tram.fill"
        )
        AppShortcut(
            intent: UpdateDutyCountdownIntent(),
            phrases: ["用 \(.applicationName) 更新更份倒數", "\(.applicationName) 更份倒數"],
            shortTitle: "更新更份倒數",
            systemImageName: "timer"
        )
        AppShortcut(
            intent: EndDutyCountdownIntent(),
            phrases: ["用 \(.applicationName) 結束更份倒數"],
            shortTitle: "結束更份倒數",
            systemImageName: "stop.circle"
        )
    }
}
