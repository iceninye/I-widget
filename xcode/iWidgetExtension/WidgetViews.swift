import SwiftUI
import WidgetKit

struct StatsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StatsEntry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallView(entry: entry)
        case .systemMedium:
            MediumView(entry: entry)
        case .systemLarge, .systemExtraLarge:
            LargeView(entry: entry)
        case .accessoryInline:
            InlineView(entry: entry)
        case .accessoryCircular:
            CircularView(entry: entry)
        case .accessoryRectangular:
            RectangularView(entry: entry)
        default:
            LargeView(entry: entry)
        }
    }
}

// MARK: - Home Screen

struct SmallView: View {
    let entry: StatsEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DateHeader(date: entry.date, size: 13, lowPower: entry.stats.isLowPowerMode, refresh: .icon)
            Spacer(minLength: 0)
            ClockText(date: entry.date, size: 44)
            Spacer(minLength: 0)
            BatteryChip(entry: entry)
        }
    }
}

struct MediumView: View {
    let entry: StatsEntry

    var body: some View {
        let stats = entry.stats
        let lowStorage = Formatting.isLowStorage(free: stats.freeBytes, total: stats.totalBytes)
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                DateHeader(date: entry.date, size: 14, lowPower: stats.isLowPowerMode, refresh: .icon)
                Spacer(minLength: 0)
                ClockText(date: entry.date, size: 48)
                WeatherLine(weather: entry.info.weather)
            }
            VStack(spacing: 8) {
                CompactStat(
                    symbol: entry.batterySymbol,
                    tint: entry.batteryTone.color,
                    value: entry.batteryText,
                    valueColor: entry.batteryTone.color,
                    fraction: stats.batteryLevel
                )
                CompactStat(
                    symbol: "internaldrive.fill",
                    tint: lowStorage ? .red : .blue,
                    value: "\(Formatting.bytes(stats.freeBytes)) 可用",
                    valueColor: lowStorage ? .red : .primary,
                    fraction: Formatting.usedFraction(free: stats.freeBytes, total: stats.totalBytes)
                )
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct LargeView: View {
    let entry: StatsEntry

    var body: some View {
        let stats = entry.stats
        let lowStorage = Formatting.isLowStorage(free: stats.freeBytes, total: stats.totalBytes)
        VStack(spacing: 6) {
            DateHeader(date: entry.date, size: 15, lowPower: stats.isLowPowerMode, refresh: .full)
            Spacer(minLength: 0)
            ClockText(date: entry.date, size: 56)
                .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
            StatCard(
                symbol: entry.batterySymbol,
                tint: entry.batteryTone.color,
                title: "電量",
                value: batteryValue,
                valueColor: entry.batteryTone.color,
                fraction: stats.batteryLevel
            )
            StatCard(
                symbol: "internaldrive.fill",
                tint: lowStorage ? .red : .blue,
                title: "儲存空間",
                value: Formatting.storagePair(free: stats.freeBytes, total: stats.totalBytes),
                valueColor: lowStorage ? .red : .primary,
                fraction: Formatting.usedFraction(free: stats.freeBytes, total: stats.totalBytes)
            )
            StatCard(
                symbol: "clock.fill",
                tint: entry.rebootHint.tint,
                title: "開機時間",
                value: entry.uptimeText + entry.rebootHint.suffix,
                valueColor: entry.rebootHint.valueColor
            )
            StatCard(
                symbol: "iphone.gen3",
                tint: .gray,
                title: "系統版本",
                value: versionValue,
                valueColor: versionColor
            )
            StatCard(
                symbol: entry.info.weather.map { WeatherCode.symbol($0.today.code) } ?? "cloud.fill",
                tint: .cyan,
                title: "天氣",
                value: weatherValue
            )
            StatCard(
                symbol: "dollarsign.circle.fill",
                tint: .yellow,
                title: "黃金 USD/oz",
                value: Formatting.gold(entry.info.gold?.usdPerOunce),
                valueColor: Formatting.isStale(entry.info.gold?.fetchedAt, now: entry.info.updatedAt) ? .secondary : .primary
            )
            Text("資料更新於 \(Formatting.clock(entry.info.updatedAt))")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    private var versionValue: String {
        switch entry.osStatus {
        case .updateAvailable(let latest): return "\(entry.stats.versionText) → \(latest)"
        case .upToDate: return "\(entry.stats.versionText) · 最新"
        case .unknown: return entry.stats.versionText
        }
    }

    private var versionColor: Color {
        if case .updateAvailable = entry.osStatus { return .orange }
        return .primary
    }

    private var weatherValue: String {
        guard let weather = entry.info.weather else { return Formatting.missing }
        let tomorrow = weather.tomorrow.map { " · 明 \(Formatting.tempRange($0))" } ?? ""
        return "\(Formatting.degrees(weather.currentTemp)) · 今 \(Formatting.tempRange(weather.today))\(tomorrow)"
    }

    private var batteryValue: String {
        var text = entry.batteryText
        if entry.stats.isCharging {
            text += entry.stats.isFullyCharged ? " · 已充滿" : " · 充電中"
        }
        return text
    }
}

// MARK: - Lock Screen

struct InlineView: View {
    let entry: StatsEntry

    var body: some View {
        Text("\(Formatting.weekday(entry.date)) \(Formatting.monthDay(entry.date)) · \(entry.batteryText)")
    }
}

struct CircularView: View {
    let entry: StatsEntry

    var body: some View {
        Gauge(value: entry.stats.batteryLevel ?? 0) {
            Image(systemName: entry.batterySymbol)
        } currentValueLabel: {
            Text(entry.batteryText)
        }
        .gaugeStyle(.accessoryCircularCapacity)
    }
}

struct RectangularView: View {
    let entry: StatsEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(Formatting.weekday(entry.date)) \(Formatting.monthDay(entry.date))")
                .font(.system(size: 12, weight: .semibold))
                .widgetAccentable()
            ClockText(date: entry.date, size: 26)
            HStack(spacing: 4) {
                Image(systemName: entry.batterySymbol)
                Text(entry.batteryText)
            }
            .font(.system(size: 12))
        }
    }
}
