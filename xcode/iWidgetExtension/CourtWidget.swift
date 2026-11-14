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
    /// 最後**任一**法院成功取得案件表嘅時間（唔係「全部法院都成功」）；一個都冇成功記錄就 nil，標題顯示「未有資料」。
    let updatedAt: Date?
    let theme: WidgetTheme

    static let sample = CourtEntry(
        date: Date(),
        days: [
            CourtDay(code: "DC", dateCode: "", total: 42, cases: [
                CourtCase(room: "第 3 庭", judge: "法官", minutes: 570, caseNo: "DCCJ 1/2026", nature: "聆訊"),
                CourtCase(room: "第 5 庭", judge: "法官", minutes: 600, caseNo: "DCCC 2/2026", nature: "審訊"),
                CourtCase(room: "第 8 庭", judge: "法官", minutes: 630, caseNo: "DCPI 3/2026"),
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
        // snapshot 唔上網，用快取：更新時間都要用快取入面嘅真實成功時間，唔可以話係「而家」
        let days = codes(configuration).map { CourtList.cached(code: $0, day: day) }
        return CourtEntry(
            date: now, days: days,
            listDate: day, updatedAt: CourtList.lastSuccess(days: days), theme: WidgetTheme.load()
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
        // 只有真係成功取得案件表嘅法院先計；全部失敗／冇快取就 nil（標題顯示「未有資料」），唔使 now 灌水
        let success = CourtList.lastSuccess(days: days)

        var dates = (0..<12).map { now.addingTimeInterval(Double($0) * 600) }
        // 18:30 轉去下一個工作天嘅案件表
        let calendar = ICalendar.hongKong
        if let next = calendar.nextDate(after: now, matching: DateComponents(hour: 18, minute: 30), matchingPolicy: .nextTime),
           next < now.addingTimeInterval(2 * 3_600) {
            dates.append(next)
        }
        let entries = dates.sorted().map {
            CourtEntry(date: $0, days: days, listDate: day, updatedAt: success, theme: theme)
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
        .description("司法機構法庭日誌：按類別（刑事、民事、家事、上訴…）上色，列出時間、案號、法庭、案件類型、聆訊性質、控罪同法官；唔顯示訴訟各方。")
        .supportedFamilies(withExtraLargePortrait([.systemLarge, .systemExtraLarge]))
    }
}

struct CourtWidgetView: View {
    let entry: CourtEntry

    private var minute: Int? { CourtList.minuteOfDay(now: entry.date, listDate: entry.listDate) }

    /// 標題列、每個法院卡嘅框／標題／分類統計，加埋一個聆訊（兩行）嘅高度（pt）；用嚟由 widget 高度推算放得落幾多個。
    private enum Metrics {
        static let header: CGFloat = 26
        static let section: CGFloat = 50
        static let row: CGFloat = 28
        /// 有控罪／性質嗰行多一行字
        static let rowWithCharge: CGFloat = 38
    }

    var body: some View {
        GeometryReader { geometry in
            let lists = entry.days.map { $0.upcoming(afterMinute: minute) }
            let free = geometry.size.height - Metrics.header - CGFloat(entry.days.count) * Metrics.section
            // 任何一個要畫嘅聆訊有控罪就按較高嘅行高算，放唔落嘅會收埋入「尚有 N 宗」
            let rowHeight = lists.contains { $0.contains { $0.charge != nil } } ? Metrics.rowWithCharge : Metrics.row
            let budget = max(Int(free / rowHeight), entry.days.count)
            let rows = CourtLayout.allocate(counts: lists.map(\.count), budget: budget)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "building.columns.fill").foregroundStyle(.secondary).widgetAccentable()
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
                ForEach(Array(entry.days.enumerated()), id: \.offset) { index, day in
                    CourtSection(day: day, upcoming: lists[index], minute: minute, rows: rows[index])
                }
                Spacer(minLength: 0)
            }
        }
        .widgetURL(entry.days.first.map { CourtLink(code: $0.code).url })
    }
}

private struct CourtSection: View {
    let day: CourtDay
    let upcoming: [CourtCase]
    let minute: Int?
    let rows: Int

    var body: some View {
        // 放得落全部就全部畫；放唔落就留最後一行做「尚有 N 宗」
        let hidden = max(upcoming.count - rows, 0)
        let shown = hidden > 0 ? max(rows - 1, 0) : upcoming.count
        GlassCard(padding: 6) {
            VStack(alignment: .leading, spacing: 3) {
                Link(destination: CourtLink(code: day.code).url) { header }
                if !day.error, day.total > 0 { summary }
                ForEach(Array(upcoming.prefix(shown).enumerated()), id: \.offset) { _, item in
                    Link(destination: item.link(code: day.code).url) { row(item) }
                }
                if hidden > 0 {
                    Link(destination: CourtLink(code: day.code).url) {
                        Text("尚有 \(upcoming.count - shown) 宗 · 撳入 app 睇全部")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                if !day.error, day.total > 0, upcoming.isEmpty {
                    Text("今日聆訊已完").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(day.name).font(.system(size: 12, weight: .semibold))
            if day.error {
                Badge(text: "讀取失敗", color: .orange)
            } else if day.total == 0 {
                Badge(text: "未有案件表")
            } else if minute != nil, upcoming.count != day.total {
                Badge(text: "餘 \(upcoming.count) / \(day.total) 宗", color: .blue)
            } else {
                Badge(text: "\(day.total) 宗", color: .blue)
            }
            Spacer(minLength: 0)
            if let next = upcoming.first(where: { $0.status(atMinute: minute) == .upcoming }) {
                Text("下一庭 \(next.timeText)")
                    .font(.system(size: 11, weight: .medium)).monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
        }
    }

    /// 全日案件按類別點數：刑事 12 · 民事 8 …
    private var summary: some View {
        HStack(spacing: 8) {
            ForEach(day.categoryCounts, id: \.category) { item in
                HStack(spacing: 3) {
                    Circle().fill(item.category.color).frame(width: 6, height: 6).widgetAccentable()
                    Text("\(item.category.title) \(item.count)").monospacedDigit()
                }
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 9.5))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    /// 兩行一個聆訊：時間、案號、法庭／類別、類型 · 性質、法官。行頭色條 = 類別。
    private func row(_ item: CourtCase) -> some View {
        let status = item.status(atMinute: minute)
        let type = item.caseType
        return HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(type.category.color)
                .frame(width: 3)
                .widgetAccentable()
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(item.timeText).monospacedDigit().fontWeight(.semibold)
                    Text(item.caseNo).fontWeight(.medium)
                        .lineLimit(1).minimumScaleFactor(0.7).layoutPriority(1)
                    if status == .ongoing {
                        Text("進行中").font(.system(size: 9, weight: .bold)).foregroundStyle(.green)
                    }
                    Spacer(minLength: 0)
                    Text(item.room).lineLimit(1).minimumScaleFactor(0.7).foregroundStyle(.secondary)
                }
                .font(.system(size: 11))
                HStack(spacing: 4) {
                    Text(type.category.title)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(type.category.color)
                    Text(item.detailText).lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                    Text(item.judge).lineLimit(1).minimumScaleFactor(0.7)
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                if let charge = item.charge {
                    Text(charge)
                        .font(.system(size: 9.5))
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
