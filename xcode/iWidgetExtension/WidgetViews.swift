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
        VStack(spacing: 8) {
            DateHeader(date: entry.date, size: 15, lowPower: stats.isLowPowerMode, refresh: .full)
            Spacer(minLength: 0)
            ClockText(date: entry.date, size: 80)
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
            StatCard(symbol: "iphone.gen3", tint: .gray, title: "系統版本", value: stats.versionText)
        }
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
