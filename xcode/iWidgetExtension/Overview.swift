import AppIntents
import SwiftUI
import WidgetKit

/// 今日咭 widget 嘅設定：長按 widget →「編輯小工具」。
/// token 等同密碼，只存喺 iPhone 嘅 widget 設定，唔會寫入 repo。
struct OverviewConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "今日咭設定"
    static var description = IntentDescription("tml-roster 同步 token。")

    @Parameter(title: "tml-roster 同步 token")
    var rosterToken: String?
}

/// 各項 info widget 嘅設定：VPS 網址已預設，只要填 VPS token。
struct InfoConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "資訊設定"
    static var description = IntentDescription("VPS token；VPS 網址已預設，唔使填。")

    @Parameter(title: "VPS 狀態網址（留空用預設）")
    var statusURL: String?

    @Parameter(title: "VPS token")
    var vpsToken: String?
}

/// 今日咭同資訊兩個 widget 共用嘅 provider：每 30 分鐘重讀一次（一日 48 次，喺 WidgetKit 預算內）；
/// 中間每 10 分鐘一個 entry，等開機時間、更份進度條同香港午夜／04:00 轉日都會自己更新。
/// 倒數用系統計時字，唔使 entry。今日咭只讀更份同學校日程，資訊只讀天氣、黃金、VPS 等，各自慳流量。
struct OverviewProvider<Intent: WidgetConfigurationIntent>: AppIntentTimelineProvider {
    enum Part { case today, info }

    struct Settings {
        var rosterToken: String?
        var statusURL: String?
        var vpsToken: String?
    }

    let part: Part
    let settings: @Sendable (Intent) -> Settings

    func placeholder(in context: Context) -> OverviewEntry { .sample }

    func snapshot(for configuration: Intent, in context: Context) async -> OverviewEntry {
        if context.isPreview { return .sample }
        let now = Date()
        let config = settings(configuration)
        let stats = SystemStats.read()
        let reading = Self.recordBattery(stats, now: now)
        return OverviewEntry(
            date: now, stats: stats, battery: reading.estimate, info: .cached(now: now),
            schedule: .cached(token: config.rosterToken), vps: .cached(url: config.statusURL, token: config.vpsToken), updatedAt: now,
            batteryRate: reading.rate, flips: FlipState.load(), theme: WidgetTheme.load()
        )
    }

    func timeline(for configuration: Intent, in context: Context) async -> Timeline<OverviewEntry> {
        let now = Date()
        let config = settings(configuration)
        let stats = SystemStats.read()
        let reading = Self.recordBattery(stats, now: now)
        var flips = FlipState.load()
        flips.prune(now: now)
        let theme = WidgetTheme.load()

        // 剛剛撳咗資料格反轉：用快取即刻畫，唔使等上網。
        let justFlipped = DataCache.load(Date.self, key: "flipAt").map { now.timeIntervalSince($0) < 20 } ?? false
        var loadedInfo = ExtraInfo.cached(now: now)
        var loadedSchedule = ScheduleData.cached(token: config.rosterToken)
        var loadedVPS = VPSState.cached(url: config.statusURL, token: config.vpsToken)
        if !justFlipped {
            switch part {
            case .today:
                loadedSchedule = await ScheduleData.load(token: config.rosterToken, now: now)
            case .info:
                async let info = withDeadline(20, fallback: ExtraInfo.cached(now: now)) { await ExtraInfo.load(now: now) }
                async let vps = VPSState.load(url: config.statusURL, token: config.vpsToken, now: now)
                (loadedInfo, loadedVPS) = await (info, vps)
            }
            DataCache.save(now, key: "dataAt")
        }

        var dates = (0..<12).map { now.addingTimeInterval(Double($0) * 600) }
        // 昨日夜更放工嗰一刻，今日咭先轉去新一日
        let service = Days.serviceDate(now)
        for date in [Days.add(service, -1), service].compactMap({ $0 }) {
            if let day = loadedSchedule.duty(on: date), let off = day.off, let at = day.moment(atServiceSecond: off),
               at > now, at < now.addingTimeInterval(4 * 3_600) {
                dates.append(at.addingTimeInterval(1))
            }
        }
        let calendar = ICalendar.hongKong
        for hour in [0, 4] {
            if let next = calendar.nextDate(after: now, matching: DateComponents(hour: hour, minute: 0), matchingPolicy: .nextTime),
               next < now.addingTimeInterval(2 * 3_600) {
                dates.append(next)
            }
        }
        // 反轉咗嘅格到時自動轉返正面
        dates += flips.expiries(after: now).map { $0.addingTimeInterval(1) }
        let entries = dates.sorted().map {
            OverviewEntry(
                date: $0, stats: stats, battery: reading.estimate, info: loadedInfo, schedule: loadedSchedule,
                vps: loadedVPS, updatedAt: justFlipped ? (DataCache.load(Date.self, key: "dataAt") ?? now) : now,
                batteryRate: reading.rate, flips: flips, theme: theme
            )
        }
        return Timeline(entries: entries, policy: .after(now.addingTimeInterval(30 * 60)))
    }

    /// 記低今次電量，再用歷史估算剩餘時間。
    static func recordBattery(_ stats: SystemStats, now: Date) -> (estimate: BatteryEstimate, rate: Double?) {
        var history = DataCache.load([BatterySample].self, key: "batteryHistory") ?? []
        if let level = stats.batteryLevel {
            let sample = BatterySample(time: now, level: level, charging: stats.isCharging || stats.isFullyCharged)
            history = BatteryHistory.appending(sample, to: history)
            DataCache.save(history, key: "batteryHistory")
        }
        let rate = BatteryHistory.percentPerHour(history, now: now)
        if stats.isFullyCharged { return (.full, rate) }
        return (BatteryHistory.estimate(history, now: now), rate)
    }
}

/// iOS 27 嘅 iPhone 特大 widget（4×6）係 `.systemExtraLargePortrait`，要 Xcode 27（Swift 6.4）先有呢個 case；
/// 舊版 Xcode（例如 CI 嘅 26.x）會跳過，其餘尺寸照常。
private func withExtraLargePortrait(_ families: [WidgetFamily]) -> [WidgetFamily] {
    var list = families
    #if compiler(>=6.4)
    if #available(iOS 27.0, *) {
        list.append(.systemExtraLargePortrait)
    }
    #endif
    return list
}

/// 今日咭 widget。kind 維持 `IWidgetOverview`，所以已經放咗喺桌面、填咗 roster token 嘅 widget 唔會失效。
struct IWidget: Widget {
    let kind = "IWidgetOverview"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind, intent: OverviewConfigIntent.self,
            provider: OverviewProvider<OverviewConfigIntent>(part: .today) { .init(rosterToken: $0.rosterToken) }
        ) { entry in
            TodayWidgetView(entry: entry)
                .environment(\.widgetTheme, entry.theme)
                .containerBackground(for: .widget) { WidgetBackground(theme: entry.theme) }
        }
        .configurationDisplayName("今日咭")
        .description("今日更份、未來 7 日、本週概況、明日同學校日程。")
        .supportedFamilies(withExtraLargePortrait([.systemMedium, .systemLarge, .systemExtraLarge, .accessoryInline, .accessoryRectangular]))
    }
}

/// 各項 info widget：天氣警告、屯馬綫、電量、儲存、天氣、黃金、系統、VPS 等。
struct InfoWidget: Widget {
    let kind = "IWidgetInfo"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind, intent: InfoConfigIntent.self,
            provider: OverviewProvider<InfoConfigIntent>(part: .info) { .init(statusURL: $0.statusURL, vpsToken: $0.vpsToken) }
        ) { entry in
            InfoWidgetView(entry: entry)
                .environment(\.widgetTheme, entry.theme)
                .containerBackground(for: .widget) { WidgetBackground(theme: entry.theme) }
        }
        .configurationDisplayName("各項資訊")
        .description("天氣警告、屯馬綫、電量、儲存、天氣、黃金、系統版本同 VPS。")
        .supportedFamilies(withExtraLargePortrait([.systemLarge, .systemExtraLarge, .accessoryCircular]))
    }
}
