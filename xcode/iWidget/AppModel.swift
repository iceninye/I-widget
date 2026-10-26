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
        entry = OverviewEntry(
            date: now, stats: SystemStats.read(), battery: .unknown, info: .cached(now: now),
            schedule: .cached(token: AppSettings.string(AppSettings.rosterToken)),
            vps: .cached(url: AppSettings.string(AppSettings.statusURL), token: AppSettings.string(AppSettings.vpsToken)),
            updatedAt: now
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
            schedule: loaded.1, vps: loaded.2, updatedAt: now
        )
    }
}
