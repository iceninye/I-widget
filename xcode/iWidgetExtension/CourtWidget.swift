import AppIntents
import SwiftUI
import WidgetKit

/// 可以揀嘅法院（代碼對應司法機構法庭日誌嘅 court 參數）。
enum CourtChoice: String, AppEnum {
    case cfa = "CFA", cacfi = "CACFI", hcmc = "HCMC", mcl = "MCL", o14 = "O14"
    case dc = "DC", dcmc = "DCMC", fmc = "FMC", lands = "LANDS"
    case allmag = "ALLMAG", etnmag = "ETNMAG", kcmag = "KCMAG", ktmag = "KTMAG"
    case wkmag = "WKMAG", stmag = "STMAG", flmag = "FLMAG", tmmag = "TMMAG"
    case lt = "LT", smt = "SMT", crc = "CRC"

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "法院"

    static var caseDisplayRepresentations: [CourtChoice: DisplayRepresentation] = [
        .cfa: "終審法院", .cacfi: "高等法院（上訴／原訟）", .hcmc: "高等法院（聆案官）",
        .mcl: "高等法院（三分鐘內庭）", .o14: "高等法院（簡易判決）",
        .dc: "區域法院", .dcmc: "區域法院（聆案官）", .fmc: "家事法庭", .lands: "土地審裁處",
        .allmag: "所有裁判法院", .etnmag: "東區裁判法院", .kcmag: "九龍城裁判法院", .ktmag: "觀塘裁判法院",
        .wkmag: "西九龍裁判法院", .stmag: "沙田裁判法院", .flmag: "粉嶺裁判法院", .tmmag: "屯門裁判法院",
        .lt: "勞資審裁處", .smt: "小額錢債審裁處", .crc: "死因裁判法庭",
    ]
}

/// 法院 widget 嘅設定：揀最多 4 個法院。
struct CourtConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "法院設定"
    static var description = IntentDescription("揀要睇嘅法院，最多 4 個。")

    @Parameter(title: "法院", default: [.dc, .allmag, .cfa])
    var courts: [CourtChoice]
}

struct CourtEntry: TimelineEntry {
    let date: Date
    let days: [CourtDay]
    let listDate: Date
    let updatedAt: Date
    let theme: WidgetTheme

    static let sample = CourtEntry(
        date: Date(),
        days: [
            CourtDay(code: "DC", dateCode: "", total: 42, cases: [
                CourtCase(room: "第 3 庭", judge: "法官", minutes: 570, caseNo: "DCCJ 1/2026"),
                CourtCase(room: "第 5 庭", judge: "法官", minutes: 600, caseNo: "DCCC 2/2026"),
            ]),
        ],
        listDate: Date(), updatedAt: Date(), theme: .classic
    )
}

/// 法院案件表：每 30 分鐘重讀（各法院各自有 10 分鐘快取），中間每 10 分鐘一個 entry，「下一庭」會自己前進。
struct CourtProvider: AppIntentTimelineProvider {
    static let maxCourts = 4

    func placeholder(in context: Context) -> CourtEntry { .sample }

    private func codes(_ configuration: CourtConfigIntent) -> [String] {
        var seen = Set<String>()
        let unique = configuration.courts.map(\.rawValue).filter { seen.insert($0).inserted }
        return Array(unique.prefix(Self.maxCourts))
    }

    func snapshot(for configuration: CourtConfigIntent, in context: Context) async -> CourtEntry {
        if context.isPreview { return .sample }
        let now = Date()
        let day = CourtList.listDate(now: now, holidays: PublicHolidays.cached())
        return CourtEntry(
            date: now, days: codes(configuration).map { CourtList.cached(code: $0, day: day) },
            listDate: day, updatedAt: now, theme: WidgetTheme.load()
        )
    }

    func timeline(for configuration: CourtConfigIntent, in context: Context) async -> Timeline<CourtEntry> {
        let now = Date()
        let holidays = await withDeadline(12, fallback: PublicHolidays.cached()) { await PublicHolidays.load(now: now) }
        let day = CourtList.listDate(now: now, holidays: holidays)
        let codes = codes(configuration)
        let cached = codes.map { CourtList.cached(code: $0, day: day) }
        let days = await withDeadline(20, fallback: cached) { await CourtList.loadAll(codes: codes, day: day, now: now) }
        let theme = WidgetTheme.load()

        var dates = (0..<12).map { now.addingTimeInterval(Double($0) * 600) }
        // 18:30 轉去下一個工作天嘅案件表
        let calendar = ICalendar.hongKong
        if let next = calendar.nextDate(after: now, matching: DateComponents(hour: 18, minute: 30), matchingPolicy: .nextTime),
           next < now.addingTimeInterval(2 * 3_600) {
            dates.append(next)
        }
        let entries = dates.sorted().map {
            CourtEntry(date: $0, days: days, listDate: day, updatedAt: now, theme: theme)
        }
        return Timeline(entries: entries, policy: .after(now.addingTimeInterval(30 * 60)))
    }
}

struct CourtWidget: Widget {
    let kind = "IWidgetCourt"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: CourtConfigIntent.self, provider: CourtProvider()) { entry in
            CourtWidgetView(entry: entry)
                .environment(\.widgetTheme, entry.theme)
                .containerBackground(for: .widget) { WidgetBackground(theme: entry.theme) }
        }
        .configurationDisplayName("法院案件表")
        .description("司法機構法庭日誌：各法院案件數同下一庭（唔顯示訴訟各方）。")
        .supportedFamilies(withExtraLargePortrait([.systemLarge, .systemExtraLarge]))
    }
}

struct CourtWidgetView: View {
    let entry: CourtEntry
    @Environment(\.widgetFamily) private var family

    private var minute: Int? { CourtList.minuteOfDay(now: entry.date, listDate: entry.listDate) }

    /// 所有法院合共畫幾多行聆訊。
    private var rowBudget: Int { family == .systemLarge ? 10 : 24 }

    var body: some View {
        let rows = max(1, rowBudget / max(entry.days.count, 1))
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "building.columns.fill").foregroundStyle(.secondary)
                Text("法院 \(CourtList.dayText(entry.listDate, now: entry.date))")
                    .font(.system(size: 13, weight: .bold))
                Spacer(minLength: 0)
                ThemeButton()
                RefreshButton(updatedAt: entry.updatedAt)
            }
            if entry.days.isEmpty {
                Text("長按 widget →「編輯小工具」揀法院")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            ForEach(entry.days, id: \.code) { day in
                CourtSection(day: day, minute: minute, rows: rows)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct CourtSection: View {
    let day: CourtDay
    let minute: Int?
    let rows: Int

    var body: some View {
        let upcoming = day.upcoming(afterMinute: minute)
        GlassCard(padding: 6) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(day.name).font(.system(size: 12, weight: .semibold))
                    if day.error {
                        Badge(text: "讀取失敗", color: .orange)
                    } else if day.total == 0 {
                        Badge(text: "未有案件表")
                    } else {
                        Badge(text: "\(day.total) 宗", color: .blue)
                    }
                    Spacer(minLength: 0)
                    if let next = upcoming.first {
                        Text("下一庭 \(next.timeText)")
                            .font(.system(size: 11, weight: .medium)).monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(Array(upcoming.prefix(max(rows - 1, 1)).enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 6) {
                        Text(item.timeText).monospacedDigit().frame(width: 38, alignment: .leading)
                        Text(item.room).lineLimit(1).frame(width: 52, alignment: .leading)
                        Text(item.caseNo).lineLimit(1)
                        Spacer(minLength: 0)
                        Text(item.judge).lineLimit(1).foregroundStyle(.secondary)
                    }
                    .font(.system(size: 10))
                }
                if !day.error, day.total > 0, upcoming.isEmpty {
                    Text("今日聆訊已完").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
        }
    }
}
