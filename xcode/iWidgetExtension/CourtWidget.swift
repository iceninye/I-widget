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

struct CourtConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "法院設定"
    static var description = IntentDescription("預設顯示全部法院，每頁三個；可自行選擇法院。自動翻頁約每十分鐘一次，實際時間由系統安排。")

    @Parameter(title: "法院（留空顯示全部）", default: [])
    var courts: [CourtChoice]

    @Parameter(title: "每十分鐘自動翻頁", default: true)
    var autoRotate: Bool
}

struct CourtPageIntent: AppIntent {
    static var title: LocalizedStringResource = "翻閱法院案件表"

    @Parameter(title: "設定") var configurationKey: String
    @Parameter(title: "目前頁") var currentPage: Int
    @Parameter(title: "方向") var direction: Int
    @Parameter(title: "頁數") var pageCount: Int

    init() {}

    init(configurationKey: String, currentPage: Int, direction: Int, pageCount: Int) {
        self.configurationKey = configurationKey
        self.currentPage = currentPage
        self.direction = direction
        self.pageCount = pageCount
    }

    func perform() async throws -> some IntentResult {
        let page = CourtPaging.normalized(currentPage + (direction < 0 ? -1 : 1), count: pageCount)
        DataCache.save(CourtPageState(page: page, anchoredAt: Date()), key: configurationKey)
        WidgetCenter.shared.reloadTimelines(ofKind: "IWidgetCourt")
        return .result()
    }
}

struct CourtEntry: TimelineEntry {
    let date: Date
    let summaries: [CourtSummary]
    let listDate: Date
    let updatedAt: Date?
    let theme: WidgetTheme
    let page: Int
    let pageCount: Int
    let configurationKey: String

    static var sample: CourtEntry {
        let now = Date()
        let day = CourtList.listDate(now: now)
        let summaries = ["DC", "CFA", "LANDS"].map { code in
            CourtSummary(day: CourtDay(code: code, dateCode: CourtList.dateCode(day), total: 2, cases: [
                CourtCase(room: "第 3 庭", judge: "法官", minutes: 570, caseNo: "DCCJ 1/2026"),
                CourtCase(room: "第 5 庭", judge: "法官", minutes: 900, caseNo: "DCCC 2/2026"),
            ], metadata: CourtMetadata(fetchedAt: now)), at: now, listDate: day)
        }
        return CourtEntry(date: now, summaries: summaries, listDate: day, updatedAt: now, theme: .classic,
                          page: 0, pageCount: 7, configurationKey: "court.preview")
    }
}

struct CourtProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> CourtEntry { .sample }

    private func state(for key: String, now: Date) -> CourtPageState {
        if let saved = DataCache.load(CourtPageState.self, key: key) { return saved }
        let state = CourtPageState(anchoredAt: now)
        DataCache.save(state, key: key)
        return state
    }

    private func entry(at date: Date, days: [CourtDay], listDate: Date, state: CourtPageState,
                       key: String, autoRotate: Bool, theme: WidgetTheme) -> CourtEntry {
        let count = CourtPaging.pageCount(for: days.count)
        let page = state.page(at: date, count: count, autoRotate: autoRotate)
        let visible = CourtPaging.indices(page: page, courtCount: days.count).map { days[$0] }
        return CourtEntry(date: date, summaries: visible.map { CourtSummary(day: $0, at: date, listDate: listDate) },
                          listDate: listDate, updatedAt: visible.compactMap(\.metadata.fetchedAt).min(), theme: theme,
                          page: page, pageCount: count, configurationKey: key)
    }

    func snapshot(for configuration: CourtConfigIntent, in context: Context) async -> CourtEntry {
        if context.isPreview { return .sample }
        let now = Date()
        let day = CourtList.listDate(now: now)
        let codes = CourtCatalog.selection(configuration.courts.map(\.rawValue))
        let key = CourtPaging.configurationKey(codes: codes, autoRotate: configuration.autoRotate)
        return entry(at: now, days: codes.map { CourtList.cached(code: $0, day: day) }, listDate: day,
                     state: state(for: key, now: now), key: key, autoRotate: configuration.autoRotate, theme: WidgetTheme.load())
    }

    func timeline(for configuration: CourtConfigIntent, in context: Context) async -> Timeline<CourtEntry> {
        let started = Date()
        let day = CourtList.listDate(now: started)
        let codes = CourtCatalog.selection(configuration.courts.map(\.rawValue))
        let key = CourtPaging.configurationKey(codes: codes, autoRotate: configuration.autoRotate)
        let pageState = state(for: key, now: started)
        // 翻頁即用檔案快取；正常更新保留各法院獨立成功／失敗結果。
        let justPaged = started.timeIntervalSince(pageState.anchoredAt) < 10
        let cached = codes.map { CourtList.cached(code: $0, day: day) }
        let days: [CourtDay]
        if justPaged, cached.contains(where: { $0.metadata.fetchedAt != nil }) {
            days = cached
        } else {
            let page = pageState.page(at: started, count: CourtPaging.pageCount(for: codes.count), autoRotate: configuration.autoRotate)
            let visibleCodes = CourtPaging.indices(page: page, courtCount: codes.count).map { codes[$0] }
            days = await CourtList.loadAll(codes: codes, day: day, now: started, timeout: 20, visibleCodes: visibleCodes)
        }
        let now = Date()
        let theme = WidgetTheme.load()
        var byDate = [CourtList.dateCode(day): days]
        let entries = CourtPaging.dates(now: now, state: pageState, autoRotate: configuration.autoRotate).map { date in
            let targetDay = CourtList.listDate(now: date)
            let dateCode = CourtList.dateCode(targetDay)
            if byDate[dateCode] == nil {
                byDate[dateCode] = codes.map { CourtList.cached(code: $0, day: targetDay) }
            }
            return entry(at: date, days: byDate[dateCode] ?? [], listDate: targetDay, state: pageState,
                         key: key, autoRotate: configuration.autoRotate, theme: theme)
        }
        var refresh = now.addingTimeInterval(justPaged ? 10 : 30 * 60)
        if CourtList.dateCode(CourtList.listDate(now: now)) != CourtList.dateCode(day) {
            refresh = now.addingTimeInterval(1)
        } else if let boundary = ICalendar.hongKong.nextDate(after: now, matching: DateComponents(hour: 18, minute: 30), matchingPolicy: .nextTime) {
            refresh = min(refresh, boundary)
        }
        return Timeline(entries: entries, policy: .after(refresh))
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
        .description("全部法院已解析排期，每頁三個。按箭嘴翻頁，按法院開啟案號搜尋；附件請看官方原頁。")
        .supportedFamilies(withExtraLargePortrait([.systemLarge, .systemExtraLarge]))
    }
}

struct CourtWidgetView: View {
    let entry: CourtEntry
    @Environment(\.widgetFamily) private var family

    private var routeDate: String { CourtList.isoDate(entry.listDate) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Link(destination: AppRoute.court(code: nil, date: routeDate).url) {
                    Label("法院案件表", systemImage: "building.columns.fill")
                        .font(.system(size: 13, weight: .bold))
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
                ThemeButton()
                if let updatedAt = entry.updatedAt {
                    RefreshButton(updatedAt: updatedAt)
                        .accessibilityLabel("本頁最早成功讀取時間；重新整理")
                } else {
                    Button(intent: RefreshIntent()) { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.plain)
                        .accessibilityLabel("重新讀取案件表")
                }
            }
            Text("排期 \(CourtList.dayText(entry.listDate, now: entry.date))")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            ForEach(entry.summaries, id: \.code) { summary in
                Link(destination: AppRoute.court(code: summary.code, date: routeDate).url) {
                    CourtSection(summary: summary, date: entry.date, rows: family == .systemLarge ? 1 : 2)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                pageButton(direction: -1, image: "chevron.left", label: "上一頁")
                Text("\(entry.page + 1) / \(entry.pageCount)").monospacedDigit()
                pageButton(direction: 1, image: "chevron.right", label: "下一頁")
                Spacer(minLength: 0)
                Text("附件請看原頁").lineLimit(1)
                    .accessibilityLabel(CourtList.sourceNotice)
            }
            .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .widgetURL(AppRoute.court(code: nil, date: routeDate).url)
    }

    private func pageButton(direction: Int, image: String, label: String) -> some View {
        Button(intent: CourtPageIntent(configurationKey: entry.configurationKey, currentPage: entry.page,
                                      direction: direction, pageCount: entry.pageCount)) {
            Image(systemName: image).frame(width: 28, height: 24).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(entry.pageCount <= 1)
        .accessibilityLabel(label)
    }
}

private struct CourtSection: View {
    let summary: CourtSummary
    let date: Date
    let rows: Int

    var body: some View {
        GlassCard(padding: 6) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(CourtCatalog.name(summary.code)).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 0)
                    Text(statusText)
                        .font(.system(size: 11, weight: .semibold)).lineLimit(1)
                        .foregroundStyle(statusColor)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(statusColor.opacity(0.18), in: Capsule())
                        .widgetAccentable()
                        .accessibilityLabel(summary.metadata.label(total: summary.total, error: summary.error, at: date))
                }
                ForEach(Array(summary.rows.prefix(rows).enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 5) {
                        Text(item.timeText).monospacedDigit()
                        Text(item.room).lineLimit(1)
                        Text(item.caseNo).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 11))
                }
                if summary.rows.isEmpty {
                    Text(emptyText).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                        .accessibilityLabel(summary.metadata.failure ?? emptyText)
                }
                Text(freshnessText).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private var statusColor: Color {
        summary.error || summary.metadata.isStale(at: date) ? .orange : .blue
    }

    private var statusText: String {
        if summary.error { return summary.metadata.fetchedAt == nil ? "讀取失敗" : "更新失敗・舊資料" }
        if summary.metadata.source == .unavailable { return "未確認" }
        if summary.metadata.isStale(at: date) { return "快取待更新" }
        return summary.metadata.source == .officialNoList ? "官方未提供" : "解析 \(summary.total) 宗"
    }

    private var emptyText: String {
        if summary.error { return "未能更新案件表，按此查看詳情" }
        if summary.metadata.source == .officialNoList { return "原頁未提供；不代表沒有聆訊" }
        if summary.unknownTimeCount > 0 { return "未有較後排期；\(summary.unknownTimeCount) 宗時間未列" }
        return "未有較後已解析排期；非即時庭況"
    }

    private var freshnessText: String {
        guard let fetched = summary.metadata.fetchedAt else { return "未讀取成功・公布未提供" }
        let calendar = ICalendar.hongKong
        let stamp = "\(calendar.component(.month, from: fetched))/\(calendar.component(.day, from: fetched)) \(Formatting.clock(fetched))"
        return "讀取 \(stamp)・\(summary.metadata.publishedAt == nil ? "公布未提供" : "公布時間見詳情")"
    }
}
