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
        @unknown default:
            LargeView(entry: entry)
        }
    }
}

// MARK: - Home Screen

struct SmallView: View {
    let entry: StatsEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DateHeader(date: entry.date, size: 13)
            Spacer(minLength: 0)
            ClockText(date: entry.date, size: 44)
            Spacer(minLength: 0)
            HStack {
                BatteryChip(entry: entry)
                Spacer(minLength: 0)
                if entry.stats.isLowPowerMode {
                    Image(systemName: "leaf.fill").foregroundStyle(.orange).widgetAccentable()
                }
            }
        }
    }
}

struct MediumView: View {
    let entry: StatsEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                DateHeader(date: entry.date, size: 14)
                BatteryChip(entry: entry)
            }
            Spacer(minLength: 0)
            ClockText(date: entry.date, size: 56)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Image(systemName: "internaldrive.fill").foregroundStyle(.blue).widgetAccentable()
                Text("\(Formatting.bytes(entry.stats.freeBytes)) 可用")
                    .foregroundStyle(Formatting.isLowStorage(free: entry.stats.freeBytes, total: entry.stats.totalBytes) ? Color.red : Color.primary)
                Spacer(minLength: 0)
                if entry.stats.isLowPowerMode {
                    Image(systemName: "leaf.fill").foregroundStyle(.orange).widgetAccentable()
                }
            }
            .font(.system(size: 14))
        }
    }
}

struct LargeView: View {
    let entry: StatsEntry

    var body: some View {
        let stats = entry.stats
        let lowStorage = Formatting.isLowStorage(free: stats.freeBytes, total: stats.totalBytes)
        VStack(spacing: 5) {
            DateHeader(date: entry.date, size: 15, lowPower: stats.isLowPowerMode)
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
            StatCard(symbol: "clock.fill", tint: .indigo, title: "開機時間", value: entry.uptimeText)
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
