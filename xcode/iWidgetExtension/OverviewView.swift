import SwiftUI
import WidgetKit

struct OverviewView: View {
    @Environment(\.widgetFamily) private var family
    let entry: OverviewEntry

    var body: some View {
        switch family {
        case .accessoryInline: InlineView(entry: entry)
        case .accessoryCircular: CircularView(entry: entry)
        case .accessoryRectangular: RectangularView(entry: entry)
        default: LargeOverview(entry: entry)
        }
    }
}

// MARK: - 主畫面（大）

struct LargeOverview: View {
    let entry: OverviewEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            TodayCard(entry: entry)
            TomorrowLine(entry: entry)
            SchoolSection(entry: entry)
            Spacer(minLength: 0)
            TileGrid(entry: entry)
            VPSLine(vps: entry.vps)
        }
    }
}

private let weekdayNames = ["一", "二", "三", "四", "五", "六", "日"]

private func shortDate(_ date: String) -> String {
    let parts = date.split(separator: "-").compactMap { Int($0) }
    let weekday = Days.weekdayIndex(date).map { weekdayNames[$0] } ?? ""
    return parts.count == 3 ? "\(weekday) \(parts[1])/\(parts[2])" : date
}

/// 今日咭：參考 tml-roster 今日卡：更份、組別／更類、上落班時間、04:00–04:00 進度條、
/// 地點・用膳・工時、返工／放工倒數；休息日就顯示下一更。
struct TodayCard: View {
    let entry: OverviewEntry

    var body: some View {
        let schedule = entry.schedule
        let day = entry.dutyToday
        GlassCard(tint: day?.tint, padding: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(day?.title ?? "今日更份")
                        .font(.system(size: 15, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if let day { badges(day) }
                    Spacer(minLength: 2)
                    RefreshButton(updatedAt: entry.updatedAt)
                }
                if !schedule.configured {
                    message("未設定 tml-roster token：長按 widget →「編輯小工具」貼上。", .secondary)
                } else if day == nil {
                    message(schedule.rosterFailed ? "讀唔到更表，請檢查 token 同網絡。" : "更表未有今日資料。", .orange)
                } else if let day, day.hasTimes {
                    working(day)
                } else if let day {
                    resting(day)
                }
            }
        }
        .overlay(alignment: .leading) {
            if let day {
                RoundedRectangle(cornerRadius: 2).fill(day.tint).frame(width: 4).padding(.vertical, 10)
                    .widgetAccentable()
            }
        }
    }

    @ViewBuilder private func badges(_ day: DutyDay) -> some View {
        if let group = day.group { Badge(text: group) }
        if let sheet = day.datedSheet { Badge(text: sheet, color: .orange) }
        if day.isOverride { Badge(text: "改", color: .orange) }
    }

    private func message(_ text: String, _ color: Color) -> some View {
        Text(text).font(.system(size: 11)).foregroundStyle(color).lineLimit(2)
    }

    @ViewBuilder private func working(_ day: DutyDay) -> some View {
        HStack(alignment: .lastTextBaseline) {
            Text(day.times ?? "")
                .font(.system(size: 26, weight: .heavy))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 4)
            countdown(day)
        }
        ShiftBar(day: day, now: entry.date)
            .frame(height: 6)
        Text([day.route, day.mealText, day.hoursText].compactMap { $0 }.joined(separator: " · "))
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        if let hint = day.hint {
            Text(hint).font(.system(size: 10)).foregroundStyle(.orange).lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    /// 返工前倒數返工；返緊工倒數放工；放咗工就顯示下一更。系統計時字，自己會更新。
    @ViewBuilder private func countdown(_ day: DutyDay) -> some View {
        if let on = day.on.flatMap(day.moment(atServiceSecond:)),
           let off = day.off.flatMap(day.moment(atServiceSecond:)) {
            if entry.date < on {
                timer("返工", on)
            } else if entry.date < off {
                timer("放工", off)
            } else if let next = entry.schedule.nextDuty(after: day.date), let at = next.on.flatMap(next.moment(atServiceSecond:)) {
                timer("下一更", at)
            } else {
                Text("已放工").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            }
        }
    }

    private func timer(_ label: String, _ date: Date) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(label).font(.system(size: 9)).foregroundStyle(.secondary)
            Text(date, style: .relative)
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: 110, alignment: .trailing)
    }

    @ViewBuilder private func resting(_ day: DutyDay) -> some View {
        Text(day.code).font(.system(size: 24, weight: .heavy)).foregroundStyle(day.tint).widgetAccentable()
        if let next = entry.schedule.nextDuty(after: day.date) {
            Text("下一更 \(shortDate(next.date)) · \(next.title) \(next.on.map(DutyDay.clock) ?? "")")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

/// 04:00 至翌日 04:00 嘅一條時間軸，標出更份同而家。
struct ShiftBar: View {
    @Environment(\.widgetRenderingMode) private var mode
    let day: DutyDay
    let now: Date

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let position: (Double) -> CGFloat = { seconds in CGFloat(min(1, max(0, (seconds - 14_400) / 86_400))) * width }
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.22))
                if let on = day.on, let off = day.off {
                    Capsule()
                        .fill(mode == .fullColor ? day.tint : Color.primary)
                        .frame(width: max(4, position(Double(off)) - position(Double(on))))
                        .offset(x: position(Double(on)))
                        .widgetAccentable()
                }
                if let start = day.moment(atServiceSecond: 0) {
                    let seconds = now.timeIntervalSince(start)
                    if seconds >= 14_400 && seconds <= 14_400 + 86_400 {
                        Circle()
                            .fill(Color.primary)
                            .frame(width: 9, height: 9)
                            .offset(x: position(seconds) - 4.5)
                    }
                }
            }
        }
    }
}

struct TomorrowLine: View {
    let entry: OverviewEntry

    var body: some View {
        if let day = entry.dutyTomorrow {
            HStack(spacing: 6) {
                Text("明日").foregroundStyle(.secondary)
                Circle().fill(day.tint).frame(width: 6, height: 6).widgetAccentable()
                Text(day.title).fontWeight(.semibold)
                if let times = day.times { Text(times).monospacedDigit() }
                if let route = day.route { Text(route).foregroundStyle(.secondary) }
                Spacer(minLength: 0)
            }
            .font(.system(size: 12))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 4)
        }
    }
}

/// 學校：循環周 + 今日、明日活動（最多 3 行）。
struct SchoolSection: View {
    let entry: OverviewEntry

    private struct Row {
        var prefix: String
        var time: String
        var title: String
    }

    var body: some View {
        let today = entry.schoolToday
        let tomorrow = entry.schoolTomorrow
        let rows: [Row] = today.items.map { Row(prefix: "今", time: $0.allDay ? "全日" : Formatting.clock($0.start), title: $0.title) }
            + tomorrow.items.map { Row(prefix: "明", time: $0.allDay ? "全日" : Formatting.clock($0.start), title: $0.title) }
        let failed = entry.schedule.schoolFailed
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Image(systemName: "graduationcap.fill").foregroundStyle(.teal).widgetAccentable()
                Text("學校").fontWeight(.semibold)
                if let cycle = today.cycle.first { Badge(text: cycle, color: .teal) }
                if let next = tomorrow.cycle.first { Text("明 \(next)").foregroundStyle(.secondary) }
                Spacer(minLength: 0)
                if !failed.isEmpty {
                    Text("\(failed.joined(separator: "、")) 讀唔到").foregroundStyle(.orange)
                }
            }
            .font(.system(size: 11))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            if rows.isEmpty {
                Text(failed.count == SchoolCalendars.sources.count ? "學校日曆暫時讀唔到。" : "今明兩日冇學校活動。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(rows.prefix(3).enumerated()), id: \.offset) { _, row in
                HStack(spacing: 5) {
                    Text(row.prefix).foregroundStyle(row.prefix == "今" ? .teal : .secondary)
                    Text(row.time).foregroundStyle(.secondary).monospacedDigit()
                    Text(row.title).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .font(.system(size: 11))
            }
            if rows.count > 3 {
                Text("另有 \(rows.count - 3) 項").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
    }
}

/// 3 × 2 細格：電量、儲存、開機／天氣、黃金、iOS。
struct TileGrid: View {
    let entry: OverviewEntry

    var body: some View {
        let stats = entry.stats
        let lowStorage = Formatting.isLowStorage(free: stats.freeBytes, total: stats.totalBytes)
        let weather = entry.info.weather
        Grid(horizontalSpacing: 6, verticalSpacing: 6) {
            GridRow {
                Tile(
                    symbol: entry.batterySymbol, tint: entry.batteryTone.color,
                    value: Formatting.percent(stats.batteryLevel),
                    caption: BatteryHistory.text(entry.battery) ?? "電量",
                    fraction: stats.batteryLevel
                )
                Tile(
                    symbol: "internaldrive.fill", tint: lowStorage ? .red : .blue,
                    value: Formatting.bytes(stats.freeBytes),
                    caption: "可用 / \(Formatting.bytes(stats.totalBytes))",
                    fraction: Formatting.usedFraction(free: stats.freeBytes, total: stats.totalBytes)
                )
                Tile(
                    symbol: "clock.fill", tint: entry.rebootHint.tint,
                    value: Formatting.uptime(stats.uptime(at: entry.date)),
                    caption: entry.rebootHint == .none ? "開機時間" : entry.rebootHint.suffix.replacingOccurrences(of: " · ", with: ""),
                    captionColor: entry.rebootHint == .none ? .secondary : entry.rebootHint.tint
                )
            }
            GridRow {
                Tile(
                    symbol: weather.map { WeatherCode.symbol($0.today.code) } ?? "cloud.fill", tint: .cyan,
                    value: Formatting.degrees(weather?.currentTemp),
                    caption: weather.map { "\(Formatting.tempRange($0.today)) · 明 \(Formatting.tempRange($0.tomorrow))" } ?? "天氣"
                )
                Tile(
                    symbol: "dollarsign.circle.fill", tint: .yellow,
                    value: Formatting.gold(entry.info.gold?.usdPerOunce),
                    caption: "黃金 USD/oz",
                    captionColor: Formatting.isStale(entry.info.gold?.fetchedAt, now: entry.updatedAt) ? .orange : .secondary
                )
                Tile(
                    symbol: "iphone.gen3", tint: .gray,
                    value: entry.stats.systemVersion,
                    caption: versionCaption,
                    captionColor: versionColor
                )
            }
        }
    }

    private var versionCaption: String {
        switch entry.osStatus {
        case .updateAvailable(let latest): return "可更新 \(latest)"
        case .upToDate: return "iOS 最新"
        case .unknown: return "iOS"
        }
    }

    private var versionColor: Color {
        if case .updateAvailable = entry.osStatus { return .orange }
        return .secondary
    }
}

struct Tile: View {
    let symbol: String
    let tint: Color
    let value: String
    let caption: String
    var captionColor: Color = .secondary
    var fraction: Double?

    var body: some View {
        GlassCard(padding: 7) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: symbol)
                        .font(.system(size: 11))
                        .foregroundStyle(tint)
                        .widgetAccentable()
                    Text(value)
                        .font(.system(size: 14, weight: .bold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                Text(caption)
                    .font(.system(size: 9))
                    .foregroundStyle(captionColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let fraction {
                    ProgressBar(fraction: fraction, tint: tint).frame(height: 3)
                }
            }
        }
    }
}

struct VPSLine: View {
    let vps: VPSState

    var body: some View {
        GlassCard(padding: 7) {
            HStack(spacing: 6) {
                Image(systemName: "server.rack")
                    .foregroundStyle(vps.status.map { VPSAPI.health($0).color } ?? .secondary)
                    .widgetAccentable()
                Text("VPS").fontWeight(.bold)
                if !vps.configured {
                    Text("未設定（編輯小工具輸入網址同 token）").foregroundStyle(.secondary)
                } else if let status = vps.status {
                    Text(VPSAPI.updatesText(status))
                        .foregroundStyle(status.security > 0 ? .red : (status.upgradable > 0 ? .orange : .secondary))
                    if status.rebootRequired { Text("要重啟").foregroundStyle(.red) }
                    Spacer(minLength: 2)
                    service("Xray", status.xrayRunning)
                    service("Hy2", status.hysteria2Listening)
                    if vps.failed { Image(systemName: "wifi.exclamationmark").foregroundStyle(.orange) }
                } else {
                    Text("讀唔到狀態").foregroundStyle(.orange)
                }
                if vps.status == nil { Spacer(minLength: 0) }
            }
            .font(.system(size: 11))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
    }

    @ViewBuilder private func service(_ name: String, _ up: Bool?) -> some View {
        if let up {
            HStack(spacing: 2) {
                Image(systemName: up ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(up ? .green : .red)
                    .widgetAccentable()
                Text(name)
            }
        }
    }
}

// MARK: - 鎖定畫面

struct InlineView: View {
    let entry: OverviewEntry

    var body: some View {
        if let day = entry.dutyToday, let times = day.times {
            Text("\(day.title) \(times)")
        } else {
            Text("\(entry.dutyToday?.title ?? "i-widget") · \(Formatting.percent(entry.stats.batteryLevel))")
        }
    }
}

struct CircularView: View {
    let entry: OverviewEntry

    var body: some View {
        Gauge(value: entry.stats.batteryLevel ?? 0) {
            Image(systemName: entry.batterySymbol)
        } currentValueLabel: {
            Text(Formatting.percent(entry.stats.batteryLevel))
        }
        .gaugeStyle(.accessoryCircularCapacity)
    }
}

struct RectangularView: View {
    let entry: OverviewEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(entry.dutyToday?.title ?? "今日更份")
                .font(.system(size: 13, weight: .bold))
                .widgetAccentable()
            if let times = entry.dutyToday?.times {
                Text(times).font(.system(size: 15, weight: .semibold)).monospacedDigit()
            }
            HStack(spacing: 4) {
                Image(systemName: entry.batterySymbol)
                Text(Formatting.percent(entry.stats.batteryLevel))
                if let text = BatteryHistory.text(entry.battery) { Text(text) }
            }
            .font(.system(size: 11))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}
