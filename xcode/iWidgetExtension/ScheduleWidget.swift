import AppIntents
import SwiftUI
import WidgetKit

/// 日程 widget 嘅設定：長按 widget → 編輯 widget，貼上 tml-roster 嘅雲端同步 token。
/// token 等同密碼，只存喺 iPhone 嘅 widget 設定，唔會寫入 repo。
struct ScheduleConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "日程設定"
    static var description = IntentDescription("tml-roster 雲端同步 token，用嚟顯示今日同明日更份。")

    @Parameter(title: "tml-roster 同步 token")
    var rosterToken: String?
}

struct SchoolDay {
    var cycle: [String]
    var items: [CalendarOccurrence]
}

/// 一次讀到嘅原始資料；每個 entry 再按自己嘅日期計今日、明日。
struct ScheduleData {
    var roster: Roster?
    var duties: [String: DutyTime]
    var events: [CalendarEvent]
    var configured: Bool
    var rosterFailed: Bool
    var updatedAt: Date

    static let empty = ScheduleData(roster: nil, duties: [:], events: [], configured: false, rosterFailed: false, updatedAt: Date())

    static func cached(token: String?, now: Date) -> ScheduleData {
        ScheduleData(
            roster: DataCache.load(Roster.self, key: "roster"),
            duties: DataCache.load([String: DutyTime].self, key: "duties") ?? [:],
            events: DataCache.load([CalendarEvent].self, key: "school") ?? [],
            configured: RosterAPI.cleanToken(token) != nil,
            rosterFailed: false,
            updatedAt: now
        )
    }

    /// 全部一齊讀，各自失敗各自用快取；整體最多等 20 秒。
    static func load(token: String?, now: Date) async -> ScheduleData {
        let cached = cached(token: token, now: now)
        return await withDeadline(20, fallback: cached) {
            async let roster = loadRoster(token: token)
            async let duties = loadDuties()
            async let events = loadEvents(now: now)
            let (rosterResult, dutyResult, eventResult) = await (roster, duties, events)
            return ScheduleData(
                roster: rosterResult.roster,
                duties: dutyResult,
                events: eventResult,
                configured: RosterAPI.cleanToken(token) != nil,
                rosterFailed: rosterResult.failed,
                updatedAt: now
            )
        }
    }

    private static func loadRoster(token: String?) async -> (roster: Roster?, failed: Bool) {
        guard let url = RosterAPI.url(token: token) else { return (nil, false) }
        do {
            let roster = try RosterAPI.parse(try await Fetcher.data(from: url))
            DataCache.save(roster, key: "roster")
            return (roster, false)
        } catch {
            return (DataCache.load(Roster.self, key: "roster"), true)
        }
    }

    private static func loadDuties() async -> [String: DutyTime] {
        if let cached = DataCache.load([String: DutyTime].self, key: "duties"), !cached.isEmpty,
           let checked = DataCache.load(Date.self, key: "dutiesChecked"), Date().timeIntervalSince(checked) < 6 * 3_600 {
            return cached
        }
        for url in DutyBasic.urls {
            if let duties = try? DutyBasic.parse(try await Fetcher.data(from: url, timeout: 10)), !duties.isEmpty {
                DataCache.save(duties, key: "duties")
                DataCache.save(Date(), key: "dutiesChecked")
                return duties
            }
        }
        return DataCache.load([String: DutyTime].self, key: "duties") ?? [:]
    }

    private static func loadEvents(now: Date) async -> [CalendarEvent] {
        let fetched = await withTaskGroup(of: [CalendarEvent]?.self) { group in
            for source in SchoolCalendars.sources {
                group.addTask {
                    guard let url = SchoolCalendars.url(source),
                          let data = try? await Fetcher.data(from: url, timeout: 12),
                          let text = String(data: data, encoding: .utf8) else { return nil }
                    return ICalendar.relevant(ICalendar.parse(text, calendar: source.name), around: now)
                }
            }
            var all: [CalendarEvent] = []
            var succeeded = 0
            for await result in group {
                if let result { all += result; succeeded += 1 }
            }
            return succeeded == SchoolCalendars.sources.count ? all : nil
        }
        if let fetched {
            DataCache.save(fetched, key: "school")
            return fetched
        }
        return DataCache.load([CalendarEvent].self, key: "school") ?? []
    }

    // MARK: 某日

    func duty(on serviceDate: String) -> DaySummary? {
        roster.flatMap { RosterSummary.summary(roster: $0, duties: duties, date: serviceDate) }
    }

    func school(dayStart: Date) -> SchoolDay {
        let items = ICalendar.occurrences(of: events, onDayStarting: dayStart)
        return SchoolDay(
            cycle: items.filter { $0.calendar == SchoolCalendars.cycleName }.map(\.title),
            items: items.filter { $0.calendar != SchoolCalendars.cycleName }
        )
    }
}

/// 逾時就用 fallback，唔令 widget 卡住。
func withDeadline<T: Sendable>(_ seconds: Double, fallback: T, operation: @escaping @Sendable () async -> T) async -> T {
    await withTaskGroup(of: T.self) { group in
        group.addTask { await operation() }
        group.addTask {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return fallback
        }
        let first = await group.next() ?? fallback
        group.cancelAll()
        return first
    }
}

struct ScheduleEntry: TimelineEntry {
    let date: Date
    let data: ScheduleData

    private var hongKong: Calendar { ICalendar.hongKong }

    private var todayStart: Date { hongKong.startOfDay(for: date) }
    private var tomorrowStart: Date { hongKong.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart }

    var serviceToday: String { Days.serviceDate(date) }
    var serviceTomorrow: String { Days.add(serviceToday, 1) ?? serviceToday }

    var dutyToday: DaySummary? { data.duty(on: serviceToday) }
    var dutyTomorrow: DaySummary? { data.duty(on: serviceTomorrow) }
    var schoolToday: SchoolDay { data.school(dayStart: todayStart) }
    var schoolTomorrow: SchoolDay { data.school(dayStart: tomorrowStart) }

    static let sample = ScheduleEntry(date: Date(), data: ScheduleData(
        roster: nil, duties: [:],
        events: [
            CalendarEvent(title: "Cycle 3 Day 4", start: ICalendar.hongKong.startOfDay(for: Date()), end: ICalendar.hongKong.startOfDay(for: Date()).addingTimeInterval(86_400), allDay: true, calendar: SchoolCalendars.cycleName, rule: nil),
            CalendarEvent(title: "家長日", start: Date(), end: Date().addingTimeInterval(3_600), allDay: false, calendar: "事項", rule: nil),
        ],
        configured: true, rosterFailed: false, updatedAt: Date()
    ))
}

struct ScheduleProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ScheduleEntry { .sample }

    func snapshot(for configuration: ScheduleConfigIntent, in context: Context) async -> ScheduleEntry {
        if context.isPreview { return .sample }
        return ScheduleEntry(date: Date(), data: ScheduleData.cached(token: configuration.rosterToken, now: Date()))
    }

    /// 現在、下一個香港午夜（學校日曆轉日）、下一個 04:00（更份轉服務日）各一個 entry，
    /// 之後 30 分鐘重讀。
    func timeline(for configuration: ScheduleConfigIntent, in context: Context) async -> Timeline<ScheduleEntry> {
        let now = Date()
        let data = await ScheduleData.load(token: configuration.rosterToken, now: now)
        let calendar = ICalendar.hongKong
        var dates = [now]
        for hour in [0, 4] {
            if let next = calendar.nextDate(after: now, matching: DateComponents(hour: hour, minute: 0), matchingPolicy: .nextTime) {
                dates.append(next)
            }
        }
        let entries = dates.sorted().map { ScheduleEntry(date: $0, data: data) }
        return Timeline(entries: entries, policy: .after(now.addingTimeInterval(30 * 60)))
    }
}

// MARK: - 畫面

struct ScheduleView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ScheduleEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("日程").fontWeight(.bold)
                Spacer(minLength: 0)
                Text("更新 \(Formatting.clock(entry.data.updatedAt))").foregroundStyle(.secondary)
                RefreshButton()
            }
            .font(.system(size: 11))
            if !entry.data.configured {
                Text("未設定 token：長按 widget → 編輯 widget，貼上 tml-roster 同步 token。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else if entry.data.rosterFailed && entry.data.roster == nil {
                Text("讀唔到更表，請檢查 token 同網絡。")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }
            HStack(alignment: .top, spacing: 10) {
                DayColumn(title: "今日", duty: entry.dutyToday, school: entry.schoolToday, maxItems: family == .systemLarge ? 6 : 2)
                DayColumn(title: "明日", duty: entry.dutyTomorrow, school: entry.schoolTomorrow, maxItems: family == .systemLarge ? 6 : 2)
            }
            Spacer(minLength: 0)
        }
    }
}

struct DayColumn: View {
    let title: String
    let duty: DaySummary?
    let school: SchoolDay
    let maxItems: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            if let duty {
                VStack(alignment: .leading, spacing: 1) {
                    Text(duty.label).font(.system(size: 13, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                    if let times = duty.times { Text(times).font(.system(size: 12)).monospacedDigit() }
                    if let places = duty.places {
                        Text(places).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
                .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            if !school.cycle.isEmpty {
                Label(school.cycle.joined(separator: " · "), systemImage: "repeat")
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            ForEach(Array(school.items.prefix(maxItems).enumerated()), id: \.offset) { _, item in
                HStack(spacing: 4) {
                    Text(item.allDay ? "全日" : Formatting.clock(item.start))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Text(item.title).lineLimit(1)
                }
                .font(.system(size: 11))
            }
            if school.items.count > maxItems {
                Text("另有 \(school.items.count - maxItems) 項").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

struct ScheduleWidget: Widget {
    let kind = "IWidgetSchedule"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ScheduleConfigIntent.self, provider: ScheduleProvider()) { entry in
            ScheduleView(entry: entry)
                .containerBackground(for: .widget) { WidgetBackground() }
        }
        .configurationDisplayName("日程")
        .description("今日同明日嘅更份（tml-roster）同學校日曆。")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}
