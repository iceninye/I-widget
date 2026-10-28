import SwiftUI
import WidgetKit

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

struct TodayLayout: View {
    let entry: OverviewEntry

    var body: some View {
        ViewThatFits(in: .vertical) {
            VStack(alignment: .leading, spacing: 7) {
                TodayCard(entry: entry)
                Link(destination: AppRoute.today.url) {
                    HStack {
                        Text("明日 · \(entry.dutyTomorrow?.title ?? "未有資料")").lineLimit(1)
                        Spacer(minLength: 4)
                        Text("詳情").foregroundStyle(.secondary)
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }
                    .font(.system(size: 12))
                }
                .buttonStyle(.plain)
            }
            TodayCard(entry: entry)
        }
    }
}

struct TodayCard: View {
    let entry: OverviewEntry

    var body: some View {
        let day = entry.dutyToday
        GlassCard(tint: day?.tint, padding: 8) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(day?.title ?? "今日更份").font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    if day?.isOverride == true { Badge(text: "改更", color: .orange) }
                    Spacer(minLength: 2)
                    ThemeButton()
                    RefreshButton(updatedAt: entry.updatedAt)
                }
                Link(destination: AppRoute.today.url) {
                    if !entry.schedule.configured {
                        Text("長按編輯小工具，設定更表 token。")
                            .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                    } else if let day {
                        if day.hasTimes {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(alignment: .lastTextBaseline, spacing: 6) {
                                    Text(day.times ?? "")
                                        .font(.system(size: 26, weight: .semibold)).monospacedDigit()
                                        .lineLimit(1).minimumScaleFactor(0.85)
                                    Spacer(minLength: 0)
                                    countdown(day)
                                }
                                ShiftBar(day: day, now: entry.date).frame(height: 5)
                                Text([day.route, day.hoursText].compactMap { $0 }.joined(separator: " · "))
                                    .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(day.code).font(.system(size: 26, weight: .semibold)).foregroundStyle(day.tint)
                                if let next = entry.schedule.nextDuty(after: day.date) {
                                    Text("下一更 \(next.date) · \(next.on.map(DutyDay.clock) ?? "")")
                                        .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                        }
                    } else {
                        Text(entry.schedule.rosterFailed ? "更表未能更新，撳入去查看。" : "今日未有更份資料。")
                            .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private func countdown(_ day: DutyDay) -> some View {
        if let on = day.on.flatMap(day.moment(atServiceSecond:)),
           let off = day.off.flatMap(day.moment(atServiceSecond:)) {
            if entry.date < off {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(entry.date < on ? "返工" : "放工").foregroundStyle(.secondary)
                    Text(entry.date < on ? on : off, style: .relative).monospacedDigit()
                }
                .font(.system(size: 11)).lineLimit(1)
            } else {
                Text("已到落班時間").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }
}

struct ShiftBar: View {
    let day: DutyDay
    let now: Date

    var body: some View {
        let start = day.on.flatMap(day.moment(atServiceSecond:))
        let end = day.off.flatMap(day.moment(atServiceSecond:))
        let fraction: Double = {
            guard let start, let end, end > start else { return 0 }
            return now.timeIntervalSince(start) / end.timeIntervalSince(start)
        }()
        ProgressBar(fraction: fraction, tint: day.tint)
            .accessibilityLabel("更份進度")
            .accessibilityValue(Formatting.percent(min(max(fraction, 0), 1)))
    }
}

struct InfoLayout: View {
    let entry: OverviewEntry

    var body: some View {
        ViewThatFits(in: .vertical) {
            stack(compact: false)
            stack(compact: true)
        }
    }

    private func stack(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Label("各項資訊", systemImage: "square.grid.2x2")
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 0)
                ThemeButton()
                RefreshButton(updatedAt: entry.updatedAt)
            }
            InfoSection(entry: entry)
            weather
            environment
            SchoolSection(entry: entry, compact: compact)
            HStack(spacing: 12) {
                Link(destination: AppRoute.finance.url) { Label("財經", systemImage: "chart.line.uptrend.xyaxis") }
                Link(destination: AppRoute.device.url) { Label("裝置", systemImage: "iphone") }
                Spacer(minLength: 0)
                Link(destination: AppRoute.info.url) { Label("全部", systemImage: "chevron.right") }
            }
            .font(.system(size: 12))
            .buttonStyle(.plain)
            .frame(minHeight: 24)
            Spacer(minLength: 0)
        }
    }

    private var weather: some View {
        let weather = entry.info.weather
        let stale = Formatting.isStale(weather?.observedAt, now: entry.date)
        return Link(destination: AppRoute.weather.url) {
            GlassCard(padding: 7) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(weather?.station ?? "香港天文台")
                            .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            Text(Formatting.degrees(weather?.currentTemp))
                                .font(.system(size: 27, weight: .semibold)).monospacedDigit()
                            Text(weather?.currentCode.map(WeatherCode.text) ?? "未有實況")
                                .font(.system(size: 12)).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 5) {
                        Image(systemName: weather?.currentCode.map(WeatherCode.symbol) ?? "cloud")
                            .font(.system(size: 22)).foregroundStyle(.blue).widgetAccentable()
                        Text(stale ? "資料較舊／未更新" : weather?.observedAt.map { Formatting.clock($0, calendar: ICalendar.hongKong) } ?? "未更新")
                            .font(.system(size: 11)).foregroundStyle(stale ? Color.orange : .secondary).lineLimit(1)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var environment: some View {
        let air = entry.info.air
        let weather = entry.info.weather
        let uv = weather?.uvIndex
        return HStack(spacing: 8) {
            metric("AQHI · 中西區", value: air.map { "\($0.index) · \($0.level)" } ?? "未有資料", symbol: "leaf",
                   warning: air?.isPoor ?? false, date: air?.observedAt, stale: air?.isStale(at: entry.date) ?? true)
            metric("紫外線 · 京士柏", value: uv.map { String(format: "%.1f · %@", $0, UVLevel.text($0)) } ?? "未提供", symbol: "sun.max",
                   warning: (uv ?? 0) >= 8, date: weather?.observedAt, stale: Formatting.isStale(weather?.observedAt, now: entry.date))
        }
    }

    private func metric(_ label: String, value: String, symbol: String, warning: Bool, date: Date?, stale: Bool) -> some View {
        Link(destination: AppRoute.weather.url) {
            GlassCard(padding: 6) {
                VStack(alignment: .leading, spacing: 3) {
                    Label(label, systemImage: symbol).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    Text(value).font(.system(size: 14, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(warning ? Color.orange : .primary).lineLimit(1)
                    Text(date.map { "\(stale ? "舊資料" : "資料") \(Formatting.clock($0, calendar: ICalendar.hongKong))" } ?? "時間未提供")
                        .font(.system(size: 11)).foregroundStyle(stale ? Color.orange : .secondary).lineLimit(1)
                        .accessibilityLabel("資料時間 \(Formatting.sourceTime(date))\(stale ? "，未有最新資料" : "")")
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct InfoSection: View {
    let entry: OverviewEntry

    var body: some View {
        Link(destination: AppRoute.weather.url) {
            HStack(spacing: 5) {
                if let warnings = entry.info.currentWarnings(at: entry.date) {
                    if warnings.isEmpty {
                        Image(systemName: "checkmark.shield").foregroundStyle(.secondary)
                        Text("上次查詢未有警告")
                    } else {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(warnings.contains { $0.severe } ? Color.red : .orange)
                        Text(warnings.map(\.text).joined(separator: " · "))
                            .foregroundStyle(warnings.contains { $0.severe } ? Color.red : .orange)
                    }
                } else {
                    Image(systemName: "wifi.exclamationmark").foregroundStyle(.secondary)
                    Text("最新警告未能確認")
                }
                Spacer(minLength: 0)
                if let train = entry.info.currentTrain(at: entry.date), train.state != .normal {
                    Image(systemName: "tram.fill").foregroundStyle(.orange)
                    Text(train.state.text).foregroundStyle(.orange)
                }
            }
            .font(.system(size: 12)).lineLimit(2)
        }
        .buttonStyle(.plain)
    }
}

struct SchoolSection: View {
    let entry: OverviewEntry
    var compact = false

    var body: some View {
        Link(destination: AppRoute.school.url) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: "graduationcap").foregroundStyle(.teal).widgetAccentable()
                    Text("學校").fontWeight(.semibold)
                    if let cycle = entry.schoolToday.cycle.first { Text(cycle).foregroundStyle(.secondary) }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                }
                if !compact {
                    if !entry.schedule.schoolFailed.isEmpty {
                        Text("部分日曆未能更新").foregroundStyle(.orange)
                    } else if let item = entry.schoolToday.items.first {
                        Text("今 · \(item.title)").foregroundStyle(.secondary)
                    } else if let item = entry.schoolTomorrow.items.first {
                        Text("明 · \(item.title)").foregroundStyle(.secondary)
                    } else {
                        Text("今明日未有已載入活動").foregroundStyle(.secondary)
                    }
                }
            }
            .font(.system(size: 12)).lineLimit(1)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

struct InlineView: View {
    let entry: OverviewEntry
    var body: some View {
        Text([entry.dutyToday?.title ?? "今日更份", entry.dutyToday?.times].compactMap { $0 }.joined(separator: " · "))
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
        VStack(alignment: .leading, spacing: 3) {
            Text(entry.dutyToday?.title ?? "今日更份").font(.headline).widgetAccentable()
            if let times = entry.dutyToday?.times { Text(times).font(.body.weight(.semibold)).monospacedDigit() }
            Text("撳入查看更份詳情").font(.caption).foregroundStyle(.secondary)
        }
        .lineLimit(1)
    }
}
