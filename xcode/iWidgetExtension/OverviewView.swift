import SwiftUI
import WidgetKit

/// 今日咭 widget：今日咭、七日條、本週概況、明日、學校日程。
struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: OverviewEntry

    var body: some View {
        switch family {
        case .accessoryInline: InlineView(entry: entry)
        case .accessoryRectangular: RectangularView(entry: entry)
        default: TodayLayout(entry: entry)
        }
    }
}

/// 各項 info widget：天氣警告、屯馬綫、資料格、VPS。
struct InfoWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: OverviewEntry

    var body: some View {
        switch family {
        case .accessoryCircular: CircularView(entry: entry)
        default: InfoLayout(entry: entry)
        }
    }
}

// MARK: - 主畫面

struct TodayLayout: View {
    let entry: OverviewEntry

    /// 放得落就全部顯示；拉大 widget 嘅時候學校多幾行。裝唔晒就先收起學校，再收明日、本週概況、7 日色條；
    /// 最後先收今日咭嘅次要行（提示、逐時預報）同警告列，確保 systemMedium 唔會截尾。
    var body: some View {
        GeometryReader { geometry in
            let rows = geometry.size.height > 480 ? 10 : (geometry.size.height > 420 ? 6 : 3)
            ViewThatFits(in: .vertical) {
                stack(rows: rows, strip: true, week: true, tomorrow: true, school: true)
                stack(rows: rows, strip: true, week: true, tomorrow: true, school: false)
                stack(rows: rows, strip: true, week: true, tomorrow: false, school: false)
                stack(rows: rows, strip: true, week: false, tomorrow: false, school: false)
                stack(rows: rows, strip: false, week: false, tomorrow: false, school: false)
                stack(rows: rows, strip: false, week: false, tomorrow: false, school: false, compact: true)
                stack(rows: rows, strip: false, week: false, tomorrow: false, school: false, compact: true, alerts: false)
            }
        }
    }

    private func stack(
        rows: Int, strip: Bool, week: Bool, tomorrow: Bool, school: Bool,
        compact: Bool = false, alerts: Bool = true
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            TodayCard(entry: entry, compact: compact)
            if alerts { TodayAlerts(entry: entry) }
            if strip { WeekStrip(entry: entry) }
            if week { WeekLine(entry: entry) }
            if tomorrow { TomorrowLine(entry: entry) }
            if school { SchoolSection(entry: entry, maxRows: rows) }
            Spacer(minLength: 0)
        }
    }
}

struct InfoLayout: View {
    @Environment(\.widgetFamily) private var family
    let entry: OverviewEntry

    /// 資料格一行三格：多一行就多三格，所以要睇尺寸俾幾多，唔好一次過攤 12 格。
    private var maxExtraRows: Int {
        switch family {
        case .systemSmall, .systemMedium: return 0
        case .systemLarge: return 1
        default: return 2                      // iPad 特大等比 large 更大嘅尺寸
        }
    }

    /// 位唔夠就由最底一行開始收起（第 4 行記憶體、降雨、低耗電；第 3 行紫外線、空氣、匯率）。
    var body: some View {
        let extra = maxExtraRows
        ViewThatFits(in: .vertical) {
            stack(extraRows: extra)
            stack(extraRows: max(0, extra - 1))
            stack(extraRows: 0)
        }
    }

    private func stack(extraRows: Int) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Image(systemName: "square.grid.2x2.fill").foregroundStyle(.secondary).widgetAccentable()
                Text("資訊").fontWeight(.semibold)
                Spacer(minLength: 2)
                ThemeButton()
                RefreshButton(updatedAt: entry.updatedAt)
            }
            .font(.system(size: 12))
            .padding(.horizontal, 4)
            InfoSection(entry: entry)
            Spacer(minLength: 0)
            TileGrid(entry: entry, extraRows: extraRows)
            VPSLine(vps: entry.vps, flipped: entry.isFlipped("vps"), back: entry.vpsBack)
        }
    }
}

/// 本週概況一行（跟 tml-roster「本週概況」）。
struct WeekLine: View {
    let entry: OverviewEntry

    var body: some View {
        if let week = entry.weekSummary {
            Text("本週 \(week.text)")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 4)
        }
    }
}

/// 未來 7 日更份色條：星期、日期、更類標籤，顏色跟 tml-roster 更類。
struct WeekStrip: View {
    let entry: OverviewEntry

    var body: some View {
        let today = entry.serviceToday
        HStack(spacing: 3) {
            ForEach(0..<7, id: \.self) { offset in
                cell(Days.add(today, offset), isToday: offset == 0)
            }
        }
    }

    private func cell(_ date: String?, isToday: Bool) -> some View {
        let day = date.flatMap { entry.schedule.duty(on: $0) }
        let parts = (date ?? "").split(separator: "-").compactMap { Int($0) }
        let weekday = date.flatMap { Days.weekdayIndex($0) }.map { weekdayNames[$0] } ?? "—"
        let dayNumber = parts.count == 3 ? "\(parts[2])" : ""
        return VStack(spacing: 2) {
            Text("\(weekday)\(dayNumber)")
                .font(.system(size: 9))
                .foregroundStyle(isToday ? .primary : .secondary)
                .lineLimit(1)
            Text(day?.shortLabel ?? "—")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 15)
                .background(
                    day?.gradient ?? LinearGradient(colors: [Color.gray.opacity(0.55)], startPoint: .top, endPoint: .bottom),
                    in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                )
                .widgetAccentable()
                .overlay {
                    if isToday {
                        RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.primary, lineWidth: 1.5)
                    }
                }
            if let weather = date.flatMap({ entry.info.weather?.day($0) }) {
                HStack(spacing: 1) {
                    Image(systemName: WeatherCode.symbol(weather.code))
                    Text("\(Int(weather.maxTemp.rounded()))°").monospacedDigit()
                }
                .font(.system(size: 8.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private let weekdayNames = ["一", "二", "三", "四", "五", "六", "日"]

private func shortDate(_ date: String) -> String {
    let parts = date.split(separator: "-").compactMap { Int($0) }
    let weekday = Days.weekdayIndex(date).map { weekdayNames[$0] } ?? ""
    return parts.count == 3 ? "\(weekday) \(parts[1])/\(parts[2])" : date
}

/// 今日咭：參考 tml-roster 今日卡：更份、組別／更類、上落班時間、04:00–04:00 進度條、
/// 地點・工時（用膳收喺背面）、返工／放工倒數；休息日就顯示下一更。
/// 第一行只放更份＋badges＋日期；調色掣同「即時更新」放咗去天氣嗰行右邊，唔喺頭搶位。
struct TodayCard: View {
    let entry: OverviewEntry
    /// 尺寸唔夠（systemMedium）：收起提示同逐時預報呢啲次要行，主要資料同字級唔變。
    var compact = false

    var body: some View {
        let schedule = entry.schedule
        let day = entry.dutyToday
        GlassCard(tint: day?.tint, padding: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(day?.title ?? "今日更份")
                        .font(.system(size: 16, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if let day { badges(day) }
                    Spacer(minLength: 2)
                    Text(shortDate(entry.serviceToday))
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Button(intent: FlipIntent(tile: "today")) {
                    VStack(alignment: .leading, spacing: 3) {
                        if !schedule.configured {
                            message("未設定 tml-roster token：長按 widget →「編輯小工具」貼上。", .secondary)
                        } else if day == nil {
                            message(schedule.rosterFailed ? "讀唔到更表，請檢查 token 同網絡。" : "更表未有今日資料。", .orange)
                        } else if entry.isFlipped("today") {
                            BackFace(lines: entry.todayBack, size: 12)
                        } else if let day, day.hasTimes {
                            working(day)
                        } else if let day {
                            resting(day)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(spoken(day))
                if !entry.isFlipped("today"), let weather = entry.info.weather {
                    Divider().padding(.vertical, 1)
                    HStack(spacing: 5) {
                        // 天氣行都可以撳嚟反轉（同更份主體同一個 FlipIntent）；兩個掣唔可以嵌入 Button label，所以並排
                        Button(intent: FlipIntent(tile: "today")) {
                            TodayWeatherRow(weather: weather, day: compact ? nil : (day?.hasTimes == true ? day : nil), now: entry.date)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        ThemeButton()
                        RefreshButton(updatedAt: entry.updatedAt)
                    }
                } else {
                    HStack(spacing: 5) {
                        Spacer(minLength: 0)
                        ThemeButton()
                        RefreshButton(updatedAt: entry.updatedAt)
                    }
                }
            }
        }
        .overlay(alignment: .leading) {
            if let day {
                RoundedRectangle(cornerRadius: 2).fill(day.tint).frame(width: 4).padding(.vertical, 8)
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
        Text(text).font(.system(size: 12)).foregroundStyle(color).lineLimit(2)
    }

    /// 一句可讀描述：更份＋上落班時間＋地點＋工時＋倒數。
    private func spoken(_ day: DutyDay?) -> String {
        if !entry.schedule.configured { return "未設定 tml-roster token，長按小工具編輯" }
        guard let day else { return "更表未有今日資料" }
        var parts = [day.title]
        if let times = day.times { parts.append(times) }
        if let route = day.route { parts.append("喺 \(route)") }
        if let hours = day.hoursText { parts.append(hours) }
        if let next = upcoming(day) {
            parts.append("距\(next.label)仲有 \(Formatting.shortDuration(next.at.timeIntervalSince(entry.date)))")
        } else if day.hasTimes {
            parts.append("已放工")
        }
        return parts.joined(separator: "，")
    }

    @ViewBuilder private func working(_ day: DutyDay) -> some View {
        HStack(alignment: .lastTextBaseline) {
            Text(day.times ?? "")
                .font(.system(size: 26, weight: .heavy))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            countdown(day)
        }
        ShiftBar(day: day, now: entry.date)
            .frame(height: 6)
        HStack(spacing: 5) {
            if let route = day.route {
                Text(route)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            if let hours = day.hoursText {
                Text(hours)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        if !compact, let hint = day.hint {
            Text(hint).font(.system(size: 11)).foregroundStyle(.orange).lineLimit(1).minimumScaleFactor(0.8)
        }
    }

    /// 下一個要倒數嘅時刻：未返工就返工，返緊工就放工，放咗工就下一更。
    private func upcoming(_ day: DutyDay) -> (label: String, at: Date)? {
        guard let on = day.on.flatMap(day.moment(atServiceSecond:)),
              let off = day.off.flatMap(day.moment(atServiceSecond:)) else { return nil }
        if entry.date < on { return ("返工", on) }
        if entry.date < off { return ("放工", off) }
        if let next = entry.schedule.nextDuty(after: day.date), let at = next.on.flatMap(next.moment(atServiceSecond:)) {
            return ("下一更", at)
        }
        return nil
    }

    /// 返工前倒數返工；返緊工倒數放工；放咗工就顯示下一更。系統計時字，自己會更新。
    @ViewBuilder private func countdown(_ day: DutyDay) -> some View {
        if let next = upcoming(day) {
            timer(next.label, next.at)
        } else if day.hasTimes {
            Text("已放工").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
        }
    }

    private func timer(_ label: String, _ date: Date) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(date, style: .relative)
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: 110, alignment: .trailing)
    }

    @ViewBuilder private func resting(_ day: DutyDay) -> some View {
        Text(day.code).font(.system(size: 24, weight: .heavy)).foregroundStyle(day.tint).widgetAccentable()
        if let next = entry.schedule.nextDuty(after: day.date) {
            Text("下一更 \(shortDate(next.date)) · \(next.title) \(next.on.map(DutyDay.clock) ?? "")")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

/// 今日咭底部：今日天氣（而家溫度、天氣、今日高低溫、降雨機會），
/// 有上落班時間就再加返工／放工嗰個鐘嘅逐小時預報（已過嘅時段唔顯示）。
/// 而家溫度讀唔到就顯示「—」，唔好拿最高溫冒充。
struct TodayWeatherRow: View {
    let weather: WeatherSnapshot
    let day: DutyDay?
    let now: Date

    /// 而家溫度：讀唔到就顯示「—」，唔好攞最高溫冒充。
    private var tempText: String { Formatting.degrees(weather.currentTemp) }

    private var tempSpoken: String {
        weather.currentTemp == nil ? "而家溫度未有資料" : "而家 \(tempText)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: WeatherCode.symbol(weather.today.code))
                    .symbolRenderingMode(.multicolor)
                Text(tempText)
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .accessibilityLabel(tempSpoken)
                Text(WeatherCode.text(weather.today.code))
                Text("今日 \(Formatting.tempRange(weather.today))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer(minLength: 0)
                if let rain = weather.today.rainChance {
                    rainLabel(rain)
                }
            }
            if let day, !shifts(day).isEmpty {
                HStack(spacing: 10) {
                    ForEach(Array(shifts(day).enumerated()), id: \.offset) { _, item in
                        shiftForecast(item.label, item.hour)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .font(.system(size: 11))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private struct ShiftHour {
        let label: String
        let hour: WeatherHour
    }

    /// 返工、放工兩個時刻（未過去嘅）對應嘅逐小時預報。
    private func shifts(_ day: DutyDay) -> [ShiftHour] {
        let calendar = ICalendar.hongKong
        let moments: [(String, Int?)] = [("返工", day.on), ("放工", day.off)]
        return moments.compactMap { (label, seconds) -> ShiftHour? in
            guard let seconds, let at = day.moment(atServiceSecond: seconds),
                  at > now.addingTimeInterval(-3_600),
                  let hour = weather.hour(at: at, calendar: calendar) else { return nil }
            return ShiftHour(label: "\(label) \(DutyDay.clock(seconds))", hour: hour)
        }
    }

    private func shiftForecast(_ label: String, _ hour: WeatherHour) -> some View {
        HStack(spacing: 3) {
            Text(label).foregroundStyle(.secondary).monospacedDigit()
            if let code = hour.code {
                Image(systemName: WeatherCode.symbol(code)).symbolRenderingMode(.multicolor)
            }
            Text(Formatting.degrees(hour.temp)).monospacedDigit()
            if let rain = hour.rainChance, rain >= 30 {
                rainLabel(rain)
            }
        }
    }

    private func rainLabel(_ rain: Int) -> some View {
        HStack(spacing: 1) {
            Image(systemName: "umbrella.fill")
            Text("\(rain)%").monospacedDigit()
        }
        .foregroundStyle(rain >= 50 ? Color.blue : Color.secondary)
        .widgetAccentable()
    }
}

/// 今日咭下面：有天氣警告、或者屯馬綫唔正常先出現；平時唔佔位。
/// 一次過列晒好擠：最多兩條，其餘寫成「+N 項」；讀唔到（nil）同真係冇警告（空）要分開講。
struct TodayAlerts: View {
    let entry: OverviewEntry

    private static let maxVisible = 2

    var body: some View {
        let known = entry.info.warnings != nil
        let warnings = entry.info.warnings ?? []
        let train = entry.info.train
        let trainIssue = train.map { $0.state != .normal } ?? false
        if !known {
            Text("天氣警告：未有資料")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 4)
        } else if !warnings.isEmpty || trainIssue {
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(warnings.contains { $0.severe } ? Color.red : .orange)
                    .widgetAccentable()
                ForEach(Array(warnings.prefix(Self.maxVisible).enumerated()), id: \.offset) { _, warning in
                    Badge(text: warning.text, color: warning.severe ? .red : .orange)
                }
                if warnings.count > Self.maxVisible {
                    Text("+\(warnings.count - Self.maxVisible) 項").foregroundStyle(.orange)
                }
                if let train, trainIssue {
                    Badge(text: "屯馬綫 \(train.state.text)", color: .orange)
                }
                Spacer(minLength: 0)
            }
            .font(.system(size: 12))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 4)
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
            .font(.system(size: 15))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 4)
        }
    }
}

/// 學校：循環周 + 今日、明日活動（最多 3 行）。
struct SchoolSection: View {
    let entry: OverviewEntry
    var maxRows = 3

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
            .font(.system(size: 13))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            if rows.isEmpty {
                Text(failed.count == SchoolCalendars.sources.count ? "學校日曆暫時讀唔到。" : "今明兩日冇學校活動。")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(rows.prefix(maxRows).enumerated()), id: \.offset) { _, row in
                HStack(spacing: 5) {
                    Text(row.prefix).foregroundStyle(row.prefix == "今" ? .teal : .secondary)
                    Text(row.time).foregroundStyle(.secondary).monospacedDigit()
                    Text(row.title).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .font(.system(size: 13))
            }
            if rows.count > maxRows {
                Text("另有 \(rows.count - maxRows) 項").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if let holiday = entry.nextHoliday {
                HStack(spacing: 5) {
                    Image(systemName: "sun.max.fill").foregroundStyle(.orange).widgetAccentable()
                    Text(holiday.rangeText).foregroundStyle(.secondary).monospacedDigit()
                    Text(holiday.title).lineLimit(1)
                    Spacer(minLength: 0)
                    Text("\(holiday.daysAway) 日後").foregroundStyle(.secondary)
                }
                .font(.system(size: 13))
            }
        }
        .padding(.horizontal, 4)
    }
}

/// 警告、屯馬綫狀況：有事先顯眼；一次過列晒會太擠，所以最多三條，其餘寫成「+N 項」。
/// nil（讀唔到）同空陣列（真係冇警告）要分開講，唔好令人誤會。
struct InfoSection: View {
    let entry: OverviewEntry

    private static let maxVisible = 3

    var body: some View {
        let known = entry.info.warnings != nil
        let warnings = entry.info.warnings ?? []
        let train = entry.info.train
        VStack(alignment: .leading, spacing: 4) {
            if !known {
                Text("天氣警告：未有資料")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else if warnings.isEmpty {
                Text("暫無天氣警告")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(warnings.contains { $0.severe } ? Color.red : .orange)
                        .widgetAccentable()
                    ForEach(Array(warnings.prefix(Self.maxVisible).enumerated()), id: \.offset) { _, warning in
                        Badge(text: warning.text, color: warning.severe ? .red : .orange)
                    }
                    if warnings.count > Self.maxVisible {
                        Text("+\(warnings.count - Self.maxVisible) 項").foregroundStyle(.orange)
                    }
                    Spacer(minLength: 0)
                }
                .font(.system(size: 12))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
            HStack(spacing: 6) {
                if let train {
                    Image(systemName: "tram.fill")
                        .foregroundStyle(train.state == .normal ? Color.green : .orange)
                        .widgetAccentable()
                    Text("屯馬綫 \(train.state.text)")
                        .fontWeight(.semibold)
                        .foregroundStyle(train.state == .normal ? Color.primary : .orange)
                }
                Spacer(minLength: 0)
            }
            .font(.system(size: 12))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 4)
    }
}

/// 3 × 2 細格：電量、儲存、開機／天氣、黃金、iOS；有位再加紫外線、空氣、匯率，同記憶體、降雨、低耗電。
/// 預設只多加一行（9 格），多過咁就要呼叫端按 widget 尺寸決定。
struct TileGrid: View {
    let entry: OverviewEntry
    var extraRows = 1

    var body: some View {
        let stats = entry.stats
        let lowStorage = Formatting.isLowStorage(free: stats.freeBytes, total: stats.totalBytes)
        let weather = entry.info.weather
        Grid(horizontalSpacing: 6, verticalSpacing: 6) {
            GridRow {
                Tile(
                    id: "battery", symbol: entry.batterySymbol, tint: entry.batteryTone.color,
                    value: Formatting.percent(stats.batteryLevel),
                    caption: BatteryHistory.text(entry.battery) ?? "電量",
                    fraction: stats.batteryLevel,
                    flipped: entry.isFlipped("battery"), back: entry.batteryBack
                )
                Tile(
                    id: "storage", symbol: "internaldrive.fill", tint: lowStorage ? .red : .blue,
                    value: Formatting.bytes(stats.freeBytes),
                    caption: "共 \(Formatting.bytes(stats.totalBytes))",
                    fraction: Formatting.usedFraction(free: stats.freeBytes, total: stats.totalBytes),
                    flipped: entry.isFlipped("storage"), back: entry.storageBack
                )
                Tile(
                    id: "uptime", symbol: "clock.fill", tint: entry.rebootHint.tint,
                    value: Formatting.shortDuration(stats.uptime(at: entry.date)),
                    caption: entry.rebootHint == .none ? "開機時間" : entry.rebootHint.suffix.replacingOccurrences(of: " · ", with: ""),
                    captionColor: entry.rebootHint == .none ? .secondary : entry.rebootHint.tint,
                    flipped: entry.isFlipped("uptime"), back: entry.uptimeBack
                )
            }
            GridRow {
                Tile(
                    id: "weather", symbol: weather.map { WeatherCode.symbol($0.today.code) } ?? "cloud.fill", tint: .cyan,
                    value: Formatting.degrees(weather?.currentTemp),
                    caption: weather.map { "今日 \(Formatting.tempRange($0.today))" } ?? "天氣",
                    flipped: entry.isFlipped("weather"), back: entry.weatherBack
                )
                Tile(
                    id: "gold", symbol: "dollarsign.circle.fill", tint: .yellow,
                    value: Formatting.goldWhole(goldHKD?.perTael),
                    caption: goldHKD?.estimated == true ? "HK$/両 · 估算" : "HK$/両",
                    captionColor: Formatting.isStale(entry.info.gold?.fetchedAt, now: entry.date) || goldHKD?.estimated == true ? .orange : .secondary,
                    flipped: entry.isFlipped("gold"), back: entry.goldBack
                )
                Tile(
                    id: "ios", symbol: "iphone.gen3", tint: .gray,
                    value: entry.stats.systemVersion,
                    caption: versionCaption,
                    captionColor: versionColor,
                    flipped: entry.isFlipped("ios"), back: entry.osBack
                )
            }
            if extraRows >= 1 {
                GridRow {
                    uvTile
                    airTile
                    fxTile
                }
            }
            if extraRows >= 2 {
                GridRow {
                    memoryTile
                    rainTile
                    powerTile
                }
            }
        }
    }

    private var goldHKD: GoldHKD? { entry.info.gold?.hkd(rates: entry.info.fx) }

    private var memoryTile: some View {
        let stats = entry.stats
        let used = Formatting.usedFraction(free: stats.memoryAvailable, total: stats.memoryTotal)
        return Tile(
            id: "ram", symbol: "memorychip.fill", tint: (used ?? 0) > 0.9 ? .orange : .teal,
            value: Formatting.bytes(stats.memoryAvailable),
            caption: "共 \(Formatting.bytes(stats.memoryTotal))",
            fraction: used,
            flipped: entry.isFlipped("ram"), back: entry.memoryBack
        )
    }

    private var rainTile: some View {
        let weather = entry.info.weather
        let today = weather?.today.rainChance
        let tomorrow = weather?.tomorrow?.rainChance
        return Tile(
            id: "rain", symbol: "umbrella.fill", tint: (today ?? 0) >= 60 || (tomorrow ?? 0) >= 60 ? .indigo : .cyan,
            value: today.map { "\($0)%" } ?? Formatting.missing,
            caption: "降雨 · 明 \(tomorrow.map { "\($0)%" } ?? Formatting.missing)",
            fraction: today.map { Double($0) / 100 },
            flipped: entry.isFlipped("rain"), back: entry.rainBack
        )
    }

    private var powerTile: some View {
        let on = entry.stats.isLowPowerMode
        return Tile(
            id: "power", symbol: on ? "bolt.badge.clock.fill" : "bolt.fill", tint: on ? .yellow : .gray,
            value: on ? "開" : "關",
            caption: "低耗電模式",
            flipped: entry.isFlipped("power"), back: entry.batteryBack
        )
    }

    private var uvTile: some View {
        let uv = entry.info.weather?.today.uvIndex
        let tint: Color = (uv ?? 0) >= 8 ? .red : ((uv ?? 0) >= 6 ? .orange : .yellow)
        return Tile(
            id: "uv", symbol: "sun.max.trianglebadge.exclamationmark.fill", tint: tint,
            value: uv.map { "UV \(Int($0.rounded()))" } ?? Formatting.missing,
            caption: uv.map { UVLevel.text($0) } ?? "紫外線",
            flipped: entry.isFlipped("uv"), back: entry.uvBack
        )
    }

    private var airTile: some View {
        let air = entry.info.air
        return Tile(
            id: "air", symbol: "leaf.fill", tint: (air?.isPoor ?? false) ? .orange : .green,
            value: air.map { "AQI \($0.aqi)" } ?? Formatting.missing,
            caption: air?.level ?? "空氣質素",
            captionColor: (air?.isPoor ?? false) ? .orange : .secondary,
            flipped: entry.isFlipped("air"), back: entry.airBack
        )
    }

    private var fxTile: some View {
        Tile(
            id: "fx", symbol: "yensign.circle.fill", tint: .mint,
            value: entry.info.fx?.jpy.map { String(format: "%.2f", $0) } ?? Formatting.missing,
            caption: "日圓 / 港元",
            flipped: entry.isFlipped("fx"), back: entry.fxBack
        )
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

/// 撳一下反轉去背面；再撳（或者 90 秒後）轉返正面。
struct BackFace: View {
    let lines: [BackLine]
    var size: CGFloat = 11

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(lines) { line in
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(line.label).foregroundStyle(.secondary)
                    Text(line.value).fontWeight(.semibold).monospacedDigit()
                    Spacer(minLength: 0)
                }
            }
        }
        .font(.system(size: size))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

struct Tile: View {
    let id: String
    let symbol: String
    let tint: Color
    let value: String
    let caption: String
    var captionColor: Color = .secondary
    var fraction: Double?
    let flipped: Bool
    let back: [BackLine]

    /// 一句可讀描述：正面講「數值，說明」，反轉咗就照讀背面每一行。
    private var spoken: String {
        flipped
            ? back.map { "\($0.label) \($0.value)" }.joined(separator: "，")
            : "\(value)，\(caption)"
    }

    var body: some View {
        Button(intent: FlipIntent(tile: id)) {
            GlassCard(tint: flipped ? tint : nil, padding: 7) {
                if flipped {
                    BackFace(lines: back)
                        .frame(minHeight: 42, alignment: .topLeading)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: symbol)
                                .font(.system(size: 12))
                                .foregroundStyle(tint)
                                .widgetAccentable()
                            Text(value)
                                .font(.system(size: 16, weight: .bold))
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        Text(caption)
                            .font(.system(size: 11))
                            .foregroundStyle(captionColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        if let fraction {
                            ProgressBar(fraction: fraction, tint: tint).frame(height: 3)
                        } else {
                            Color.clear.frame(height: 3)
                        }
                    }
                    .frame(minHeight: 42, alignment: .topLeading)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spoken)
    }
}

struct VPSLine: View {
    let vps: VPSState
    let flipped: Bool
    let back: [BackLine]

    var body: some View {
        Button(intent: FlipIntent(tile: "vps")) {
            GlassCard(tint: flipped ? vps.status.map { VPSAPI.health($0).color } : nil, padding: 7) {
                if flipped {
                    BackFace(lines: back)
                } else {
                    front
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var front: some View {
        HStack(spacing: 6) {
            Image(systemName: "server.rack")
                .foregroundStyle(vps.status.map { VPSAPI.health($0).color } ?? .secondary)
                .widgetAccentable()
            Text("VPS").fontWeight(.bold)
            if !vps.configured {
                Text("未設定（編輯小工具輸入 VPS token）").foregroundStyle(.secondary)
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
