import AppIntents
import SwiftUI
import WidgetKit

/// 唯一一個 widget 嘅設定：長按 widget →「編輯小工具」。
/// token 同網址等同密碼，只存喺 iPhone 嘅 widget 設定，唔會寫入 repo。
struct OverviewConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "i-widget 設定"
    static var description = IntentDescription("tml-roster 同步 token 同 VPS token；VPS 網址已預設，唔使填。")

    @Parameter(title: "tml-roster 同步 token")
    var rosterToken: String?

    @Parameter(title: "VPS 狀態網址（留空用預設）")
    var statusURL: String?

    @Parameter(title: "VPS token")
    var vpsToken: String?
}

struct VPSState {
    var status: VPSStatus?
    var configured: Bool
    var failed: Bool

    static let sample = VPSState(status: .sample, configured: true, failed: false)

    static func isConfigured(url: String?, token: String?) -> Bool {
        VPSAPI.statusURL(url) != nil && !(token ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func cached(url: String?, token: String?) -> VPSState {
        VPSState(status: DataCache.load(VPSStatus.self, key: "vps"), configured: isConfigured(url: url, token: token), failed: false)
    }

    /// VPS 腳本每小時更新一次，所以 25 分鐘內讀過就用快取。
    static func load(url text: String?, token: String?, now: Date) async -> VPSState {
        guard isConfigured(url: text, token: token), let url = VPSAPI.statusURL(text) else {
            return VPSState(status: nil, configured: false, failed: false)
        }
        let cached = DataCache.load(VPSStatus.self, key: "vps")
        if let fresh = DataCache.fresh(VPSStatus.self, key: "vps", maxAge: 25 * 60, now: now) {
            return VPSState(status: fresh, configured: true, failed: false)
        }
        let bearer = (token ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let failed = VPSState(status: cached, configured: true, failed: true)
        return await withDeadline(12, fallback: failed) {
            do {
                var request = URLRequest(url: url, timeoutInterval: 10)
                request.cachePolicy = .reloadIgnoringLocalCacheData
                request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    throw URLError(.badServerResponse)
                }
                let status = try VPSAPI.parse(data)
                DataCache.save(status, key: "vps", stamped: now)
                return VPSState(status: status, configured: true, failed: false)
            } catch {
                return failed
            }
        }
    }
}

struct OverviewEntry: TimelineEntry {
    let date: Date
    let stats: SystemStats
    let battery: BatteryEstimate
    let info: ExtraInfo
    let schedule: ScheduleData
    let vps: VPSState
    let updatedAt: Date
    var batteryRate: Double? = nil
    var flips = FlipState()
    var theme = WidgetTheme.classic

    func isFlipped(_ id: String) -> Bool { flips.isFlipped(id, at: date) }

    var rebootHint: RebootHint { RebootHint.level(uptime: stats.uptime(at: date)) }
    var osStatus: OSVersionStatus { OSVersion.status(current: stats.systemVersion, latest: info.latestOS) }
    var batteryTone: BatteryTone { BatteryStyle.tone(level: stats.batteryLevel, charging: stats.isCharging) }
    var batterySymbol: String { BatteryStyle.symbol(level: stats.batteryLevel, charging: stats.isCharging) }

    /// 今日：00:00 換日；昨日夜更未放工就仍然係昨日（同 tml-roster 一致）。
    var serviceToday: String { Days.today(date) { schedule.duty(on: $0)?.off } }
    var serviceTomorrow: String { Days.add(serviceToday, 1) ?? serviceToday }
    var dutyToday: DutyDay? { schedule.duty(on: serviceToday) }
    var dutyTomorrow: DutyDay? { schedule.duty(on: serviceTomorrow) }

    private var todayStart: Date { ICalendar.hongKong.startOfDay(for: date) }
    var schoolToday: SchoolDay { schedule.school(dayStart: todayStart) }
    var schoolTomorrow: SchoolDay {
        schedule.school(dayStart: ICalendar.hongKong.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart)
    }

    /// 本週（服務日所在嘅星期一至日）概況；冇更表就 nil。
    var weekSummary: WeekSummary? {
        guard schedule.roster != nil, let monday = Days.mondayOf(serviceToday) else { return nil }
        let days = (0..<7).compactMap { Days.add(monday, $0).flatMap { schedule.duty(on: $0) } }
        return days.isEmpty ? nil : WeekSummary.make(days)
    }

    var nextHoliday: Holiday? { schedule.nextHoliday(dayStart: todayStart) }

    static var sample: OverviewEntry {
        let now = Date()
        let today = Days.serviceDate(now)
        let roster = Roster(
            rows: [Array(repeating: "1101157", count: 7)], numbers: [1], anchorRow: 1,
            anchorMonday: Days.mondayOf(today) ?? today, overrides: [Days.add(today, 1) ?? today: "RD"]
        )
        let dayStart = ICalendar.hongKong.startOfDay(for: now)
        var schedule = ScheduleData.empty
        schedule.roster = roster
        schedule.configured = true
        schedule.basic = ["1101157": DutyTime(on: 54_300, onPlace: "錦上路", off: 81_300, offPlace: "錦上路", hours: 7.5)]
        schedule.events = [
            CalendarEvent(title: "Day 4", start: dayStart, end: dayStart.addingTimeInterval(86_400), allDay: true, calendar: SchoolCalendars.cycleName, rule: nil),
            CalendarEvent(title: "中三家長會", start: dayStart.addingTimeInterval(19 * 3_600), end: dayStart.addingTimeInterval(20 * 3_600), allDay: false, calendar: "事項", rule: nil),
            CalendarEvent(title: "陸運會", start: dayStart.addingTimeInterval(86_400), end: dayStart.addingTimeInterval(2 * 86_400), allDay: true, calendar: "事項", rule: nil),
        ]
        return OverviewEntry(
            date: now, stats: .sample, battery: .remaining(5 * 3_600 + 20 * 60), info: .sample,
            schedule: schedule, vps: .sample, updatedAt: now
        )
    }
}

/// 每 30 分鐘重讀一次（一日 48 次，喺 WidgetKit 預算內）；中間每 10 分鐘一個 entry，
/// 等開機時間、更份進度條同香港午夜／04:00 轉日都會自己更新。倒數用系統計時字，唔使 entry。
struct OverviewProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> OverviewEntry { .sample }

    func snapshot(for configuration: OverviewConfigIntent, in context: Context) async -> OverviewEntry {
        if context.isPreview { return .sample }
        let now = Date()
        let stats = SystemStats.read()
        let reading = Self.recordBattery(stats, now: now)
        return OverviewEntry(
            date: now, stats: stats, battery: reading.estimate, info: .cached(now: now),
            schedule: .cached(token: configuration.rosterToken), vps: .cached(url: configuration.statusURL, token: configuration.vpsToken), updatedAt: now,
            batteryRate: reading.rate, flips: FlipState.load(), theme: WidgetTheme.load()
        )
    }

    func timeline(for configuration: OverviewConfigIntent, in context: Context) async -> Timeline<OverviewEntry> {
        let now = Date()
        let stats = SystemStats.read()
        let reading = Self.recordBattery(stats, now: now)
        var flips = FlipState.load()
        flips.prune(now: now)
        let theme = WidgetTheme.load()

        // 剛剛撳咗資料格反轉：用快取即刻畫，唔使等上網。
        let justFlipped = DataCache.load(Date.self, key: "flipAt").map { now.timeIntervalSince($0) < 20 } ?? false
        let loadedInfo: ExtraInfo
        let loadedSchedule: ScheduleData
        let loadedVPS: VPSState
        if justFlipped {
            loadedInfo = .cached(now: now)
            loadedSchedule = .cached(token: configuration.rosterToken)
            loadedVPS = .cached(url: configuration.statusURL, token: configuration.vpsToken)
        } else {
            async let info = withDeadline(20, fallback: ExtraInfo.cached(now: now)) { await ExtraInfo.load(now: now) }
            async let schedule = ScheduleData.load(token: configuration.rosterToken, now: now)
            async let vps = VPSState.load(url: configuration.statusURL, token: configuration.vpsToken, now: now)
            (loadedInfo, loadedSchedule, loadedVPS) = await (info, schedule, vps)
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

struct IWidget: Widget {
    let kind = "IWidgetOverview"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: OverviewConfigIntent.self, provider: OverviewProvider()) { entry in
            OverviewView(entry: entry)
                .environment(\.widgetTheme, entry.theme)
                .containerBackground(for: .widget) { WidgetBackground(theme: entry.theme) }
        }
        .configurationDisplayName("i-widget")
        .description("更份、學校日程、天氣、黃金、電量、系統同 VPS，一個 widget 睇晒。")
        .supportedFamilies(families)
    }

    /// iOS 27 嘅 iPhone 特大 widget（4×6）係 `.systemExtraLargePortrait`，要 Xcode 27（Swift 6.4）先有呢個 case；
    /// 舊版 Xcode（例如 CI 嘅 26.x）會跳過，其餘尺寸照常。
    private var families: [WidgetFamily] {
        var list: [WidgetFamily] = [.systemLarge, .systemExtraLarge, .accessoryInline, .accessoryCircular, .accessoryRectangular]
        #if compiler(>=6.4)
        if #available(iOS 27.0, *) {
            list.append(.systemExtraLargePortrait)
        }
        #endif
        return list
    }
}
