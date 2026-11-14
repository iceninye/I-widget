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

    func refresh() async {
        guard !loading else { return }
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
        // 開 app 係前景，Live Activity 一定啟動得到
        if DutyActivityManager.isEnabled {
            await DutyActivityManager.sync(events: entry.schedule.dutyEvents(now: now), now: now)
        }
        return alerts
    }
}
