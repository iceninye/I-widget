import Foundation
import SwiftUI

/// App 內嘅設定同資料預覽。Widget 嘅設定存喺各自嘅 widget 入面，免費簽名冇 App Group 可以共用，
/// 所以 app 要另外填一次 token，先預覽到更份同 VPS；唔填都睇到其他資料。
enum AppSettings {
    static let rosterToken = "settings.rosterToken"
    static let vpsToken = "settings.vpsToken"
    static let statusURL = "settings.statusURL"

    static func string(_ key: String) -> String? {
        let value = UserDefaults.standard.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (value ?? "").isEmpty ? nil : value
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var entry: OverviewEntry
    @Published private(set) var loading = false

    init() {
        let now = Date()
        let info = ExtraInfo.cached(now: now)
        let schedule = ScheduleData.cached(token: AppSettings.string(AppSettings.rosterToken))
        let vps = VPSState.cached(url: AppSettings.string(AppSettings.statusURL), token: AppSettings.string(AppSettings.vpsToken))
        entry = OverviewEntry(
            date: now, stats: SystemStats.read(), battery: .unknown, info: info,
            schedule: schedule, vps: vps,
            updatedAt: OverviewEntry.lastSuccess(info: info, schedule: schedule)
        )
    }

    /// 拉一次全部資料。回傳 `true` = 呢次真係跑完一輪（呼叫者先至值得叫 widget 重讀）；
    /// `false` = 已經有一個喺度跑，呢次俾 `loading` guard 阻住（唔係失敗，呼叫方唔使再 reload，
    /// 等完成嗰次 reload 就得）。`ContentView` 靠呢個返回值去串行化冷啟／deep link／返前景嘅刷新。
    @discardableResult
    func refresh() async -> Bool {
        guard !loading else { return false }
        loading = true
        defer { loading = false }
        let now = Date()
        let roster = AppSettings.string(AppSettings.rosterToken)
        let url = AppSettings.string(AppSettings.statusURL)
        let token = AppSettings.string(AppSettings.vpsToken)
        async let info = withDeadline(20, fallback: ExtraInfo.cached(now: now)) { await ExtraInfo.load(now: now) }
        async let schedule = ScheduleData.load(token: roster, now: now)
        async let vps = VPSState.load(url: url, token: token, now: now)
        let loaded = await (info, schedule, vps)
        entry = OverviewEntry(
            date: now, stats: SystemStats.read(), battery: .unknown, info: loaded.0,
            schedule: loaded.1, vps: loaded.2,
            // 真係成功取得嘅時間；全部失敗（淨係 fallback 快取）就係快取入面嘅舊時間
            updatedAt: OverviewEntry.lastSuccess(info: loaded.0, schedule: loaded.1)
        )
        // 每次開 app 都重排交接提示，跟最新更表
        await rescheduleHandover()
        return true
    }

    /// 用而家手上嘅更份資料重排提示（改設定之後唔使再上網）。回傳將會響嘅提示，設定頁預覽用。
    @discardableResult
    func rescheduleHandover() async -> [HandoverAlert] {
        let now = Date()
        let settings = HandoverSettings.load()
        let alerts = entry.schedule.handoverAlerts(now: now, settings: settings)
        if HandoverNotifier.isEnabled, await HandoverNotifier.isAuthorized() {
            await HandoverNotifier.schedule(alerts, settings: settings, now: now)
        }
        // 開 app 係前景，Live Activity 一定啟動得到。
        // 用「開咗倒數」**或者**「而家有活動行緊」都 sync：後者係為咗撳 Live Activity 入嚟（`iwidget://duty`）
        // 嗰陣，手動／捷徑開嘅活動即使設定掣唔開都更新到內容，唔會留低一舊過期倒數。
        // `sync` 內部已經串行化（見 `DutyActivityManager`）：呢度同捷徑、設定頁手動掣同時行都唔會開出重複活動。
        if DutyActivityManager.isEnabled || DutyActivityManager.isRunning {
            await DutyActivityManager.sync(events: entry.schedule.dutyEvents(now: now), now: now)
        }
        return alerts
    }
}
