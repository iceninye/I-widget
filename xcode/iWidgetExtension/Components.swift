import SwiftUI
import WidgetKit

extension BatteryTone {
    var color: Color {
        switch self {
        case .charging, .normal: return .green
        case .medium: return .orange
        case .low: return .red
        case .unknown: return .secondary
        }
    }
}

/// 大字時間（24 小時制 HH:mm）。
struct ClockText: View {
    let date: Date
    let size: CGFloat

    var body: some View {
        Text(Formatting.clock(date))
            .font(.system(size: size, weight: .bold))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }
}

/// 星期（紅）＋ 日期（灰），低耗電模式時右邊有葉仔。
struct DateHeader: View {
    let date: Date
    var size: CGFloat = 14
    var lowPower = false

    var body: some View {
        HStack(spacing: 6) {
            Text(Formatting.weekday(date))
                .fontWeight(.bold)
                .foregroundStyle(.red)
                .widgetAccentable()
            Text(Formatting.monthDay(date))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if lowPower {
                Image(systemName: "leaf.fill")
                    .foregroundStyle(.orange)
                    .widgetAccentable()
            }
        }
        .font(.system(size: size))
        .lineLimit(1)
    }
}

struct BatteryChip: View {
    let entry: StatsEntry
    var size: CGFloat = 14

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: entry.batterySymbol)
            Text(entry.batteryText).fontWeight(.semibold)
        }
        .font(.system(size: size))
        .foregroundStyle(entry.batteryTone.color)
        .widgetAccentable()
    }
}

struct ProgressBar: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(tint)
                    .frame(width: max(0, min(1, fraction)) * geometry.size.width)
            }
        }
    }
}

/// 一張資料卡：圖示 + 標題 …… [進度條] 數值。
struct StatCard: View {
    let symbol: String
    let tint: Color
    let title: String
    let value: String
    var valueColor: Color = .primary
    var fraction: Double?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: 20)
                .widgetAccentable()
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            if let fraction {
                ProgressBar(fraction: fraction, tint: tint)
                    .frame(width: 70, height: 6)
            }
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(valueColor)
        }
        .font(.system(size: 14))
        .lineLimit(1)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
