import WidgetKit
import SwiftUI

struct StatsEntry: TimelineEntry {
    let date: Date
    let stats: SystemStats
    var info = ExtraInfo.cached(now: Date.distantPast)

    var uptimeText: String { Formatting.uptime(stats.uptime(at: date)) }
    var rebootHint: RebootHint { RebootHint.level(uptime: stats.uptime(at: date)) }
    var batteryText: String { Formatting.percent(stats.batteryLevel) }
    var batteryTone: BatteryTone { BatteryStyle.tone(level: stats.batteryLevel, charging: stats.isCharging) }
    var batterySymbol: String { BatteryStyle.symbol(level: stats.batteryLevel, charging: stats.isCharging) }
    var osStatus: OSVersionStatus { OSVersion.status(current: stats.systemVersion, latest: info.latestOS) }
}

/// 只准 `run` 入面嘅嘢行一次：網絡正常就用新資料，逾時就用快取，先到先得。
final class OnceGate: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func run(_ block: () -> Void) {
        lock.lock()
        let first = !done
        done = true
        lock.unlock()
        if first { block() }
    }
}

/// 每次產生 30 個「每分鐘一個」嘅 entry，policy `.atEnd`：
/// 時鐘由 WidgetKit 按 entry 時間自動切換（唔計 reload 預算），
/// 電量、天氣、黃金等資料每 30 分鐘重讀一次（一日 48 次 reload，喺 WidgetKit 預算內）。
/// 網絡請求最多等 20 秒，逾時就用上次快取，唔會令 widget 卡住。
struct StatsProvider: TimelineProvider {
    static let entryCount = 30
    static let networkDeadline: UInt64 = 20_000_000_000

    func placeholder(in context: Context) -> StatsEntry {
        StatsEntry(date: Date(), stats: .sample, info: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (StatsEntry) -> Void) {
        let preview = context.isPreview
        completion(StatsEntry(
            date: Date(),
            stats: preview ? SystemStats.sample : SystemStats.read(),
            info: preview ? ExtraInfo.sample : ExtraInfo.cached()
        ))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StatsEntry>) -> Void) {
        let stats = SystemStats.read()
        let start = Date()
        let gate = OnceGate()

        let finish: @Sendable (ExtraInfo) -> Void = { info in
            gate.run {
                let entries = ClockTimeline
                    .minuteDates(from: start, count: Self.entryCount)
                    .map { StatsEntry(date: $0, stats: stats, info: info) }
                completion(Timeline(entries: entries, policy: .atEnd))
            }
        }

        Task { finish(await ExtraInfo.load(now: start)) }
        Task {
            try? await Task.sleep(nanoseconds: Self.networkDeadline)
            finish(ExtraInfo.cached(now: start))
        }
    }
}
