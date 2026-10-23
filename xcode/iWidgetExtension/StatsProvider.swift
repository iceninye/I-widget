import WidgetKit
import SwiftUI

struct StatsEntry: TimelineEntry {
    let date: Date
    let stats: SystemStats

    var uptimeText: String { Formatting.uptime(stats.uptime(at: date)) }
    var batteryText: String { Formatting.percent(stats.batteryLevel) }
    var batteryTone: BatteryTone { BatteryStyle.tone(level: stats.batteryLevel, charging: stats.isCharging) }
    var batterySymbol: String { BatteryStyle.symbol(level: stats.batteryLevel, charging: stats.isCharging) }
}

/// 每次產生 30 個「每分鐘一個」嘅 entry，policy `.atEnd`：
/// 時鐘由 WidgetKit 按 entry 時間自動切換（唔計 reload 預算），
/// 電量等資料每 30 分鐘重讀一次（一日 48 次 reload，喺 WidgetKit 預算內）。
struct StatsProvider: TimelineProvider {
    static let entryCount = 30

    func placeholder(in context: Context) -> StatsEntry {
        StatsEntry(date: Date(), stats: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (StatsEntry) -> Void) {
        let stats = context.isPreview ? SystemStats.sample : SystemStats.read()
        completion(StatsEntry(date: Date(), stats: stats))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StatsEntry>) -> Void) {
        let stats = SystemStats.read()
        let entries = ClockTimeline
            .minuteDates(from: Date(), count: Self.entryCount)
            .map { StatsEntry(date: $0, stats: stats) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}
