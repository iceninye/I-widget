import Foundation
import SwiftUI

/// App 內嘅設定、資料預覽同 Scriptable 匯出。Token 只留喺 app；
/// Scriptable 由 app 寫入授權資料夾嘅 JSON 讀資料，唔需要再填 token。
enum AppSettings {
    static let rosterToken = "settings.rosterToken"
    static let vpsToken = "settings.vpsToken"
    static let statusURL = "settings.statusURL"
    static let scriptableTheme = "settings.scriptableTheme"

    static func string(_ key: String) -> String? {
        let raw = [rosterToken, vpsToken, statusURL].contains(key)
            ? SecretStore.load(account: key)
            : UserDefaults.standard.string(forKey: key)
        let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (value ?? "").isEmpty ? nil : value
    }

    @discardableResult
    static func saveSecrets(rosterToken: String, vpsToken: String, statusURL: String) -> Bool {
        let rosterSaved = SecretStore.save(rosterToken, account: Self.rosterToken)
        let vpsSaved = SecretStore.save(vpsToken, account: Self.vpsToken)
        let urlSaved = SecretStore.save(statusURL, account: statusURL)
        return rosterSaved && vpsSaved && urlSaved
    }

    static func loadScriptableTheme() -> WidgetTheme {
        WidgetTheme(rawValue: UserDefaults.standard.string(forKey: scriptableTheme) ?? "") ?? .classic
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var entry: OverviewEntry
    @Published private(set) var loading = false
    let bridge = ScriptableBridgeController()

    init() {
        let now = Date()
        let info = ExtraInfo.cached(now: now)
        let schedule = ScheduleData.cached(token: AppSettings.string(AppSettings.rosterToken))
        let vps = VPSState.cached(url: AppSettings.string(AppSettings.statusURL), token: AppSettings.string(AppSettings.vpsToken))
        entry = OverviewEntry(
            date: now, stats: SystemStats.read(), battery: .unknown, info: info,
            schedule: schedule, vps: vps,
            updatedAt: OverviewEntry.lastSuccess(info: info, schedule: schedule),
            theme: AppSettings.loadScriptableTheme()
        )
        bridge.setEntry(entry)
    }

    /// 拉一次全部資料。回傳 `true` = 呢次真係跑完一輪（呼叫者先至值得叫 widget 重讀）；
    /// `false` = 已經有一個喺度跑，呢次俾 `loading` guard 阻住（唔係失敗，呼叫方唔使再 reload，
    /// 等完成嗰次 reload 就得）。`ContentView` 靠呢個返回值去串行化冷啟／deep link／返前景嘅刷新。
    @discardableResult
    func refresh(forceNetwork: Bool = false) async -> Bool {
        guard !loading else { return false }
        loading = true
        defer { loading = false }
        let now = Date()
        let loaded = await WidgetSnapshotService.load(now: now, force: forceNetwork)
        entry = loaded
        bridge.setEntry(loaded)
        // 先排通知同 Live Activity，唔使等法院／Scriptable 同步。
        await rescheduleHandover()
        if bridge.hasAuthorization {
            let courts = await WidgetSnapshotService.loadCourts(now: now, force: forceNetwork)
            bridge.setCourts(courts.days, listDate: courts.listDate)
            WidgetBackgroundRefresh.scheduleNext(hasCourtData: courts.days.contains { $0.total > 0 })
        }
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
