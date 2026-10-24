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

extension RebootHint {
    var tint: Color {
        switch self {
        case .none: return .indigo
        case .soon: return .orange
        case .due: return .red
        }
    }
}

extension ShiftClass {
    /// 同 tml-roster 嘅更類顏色一致。
    var color: Color {
        switch self {
        case .dawn: return Color(red: 0.94, green: 0.42, blue: 0.35)
        case .early: return Color(red: 0.90, green: 0.66, blue: 0.24)
        case .mid: return Color(red: 0.29, green: 0.62, blue: 0.88)
        case .late: return Color(red: 0.61, green: 0.49, blue: 0.94)
        case .night: return Color(red: 0.42, green: 0.36, blue: 0.85)
        }
    }
}

extension DutyDay {
    var tint: Color {
        switch kind {
        case .rest: return Color(red: 0.90, green: 0.25, blue: 0.30)
        case .leave: return Color(red: 0.29, green: 0.62, blue: 0.88)
        case .pending: return Color(red: 0.89, green: 0.66, blue: 0.23)
        case .spare, .other: return shift?.color ?? .gray
        case .duty: return shift?.color ?? Color(red: 0.71, green: 0.28, blue: 0.12)
        }
    }
}

extension DutyDay {
    /// 七日色條用漸變：休息日係紅色漸變（同 tml-roster 假日卡一致），其他跟更類顏色。
    var gradient: LinearGradient {
        if kind == .rest {
            return LinearGradient(
                colors: [Color(red: 1.0, green: 0.45, blue: 0.42), Color(red: 0.78, green: 0.13, blue: 0.22)],
                startPoint: .top, endPoint: .bottom
            )
        }
        let strength = kind == .duty ? 0.95 : 0.7
        return LinearGradient(
            colors: [tint.opacity(strength), tint.opacity(strength * 0.6)],
            startPoint: .top, endPoint: .bottom
        )
    }
}

extension VPSHealth {
    var color: Color {
        switch self {
        case .ok: return .green
        case .attention: return .orange
        case .problem: return .red
        }
    }
}

extension WidgetTheme {
    /// 主色；預設風格冇主色，維持原本嘅系統填色。
    var accent: Color? {
        switch self {
        case .classic: return nil
        case .ocean: return Color(red: 0.12, green: 0.55, blue: 0.95)
        case .sunset: return Color(red: 0.98, green: 0.45, blue: 0.25)
        case .forest: return Color(red: 0.18, green: 0.70, blue: 0.45)
        case .violet: return Color(red: 0.58, green: 0.38, blue: 0.95)
        case .mono: return Color.gray
        }
    }
}

private struct WidgetThemeKey: EnvironmentKey {
    static let defaultValue = WidgetTheme.classic
}

extension EnvironmentValues {
    var widgetTheme: WidgetTheme {
        get { self[WidgetThemeKey.self] }
        set { self[WidgetThemeKey.self] = newValue }
    }
}

/// 完整彩色先畫底；Clear／Tinted（Liquid Glass）由系統畫玻璃，唔好自己蓋住。
struct WidgetBackground: View {
    @Environment(\.widgetRenderingMode) private var mode
    var theme = WidgetTheme.classic

    var body: some View {
        if mode == .fullColor {
            ZStack {
                LinearGradient(
                    colors: [Color(uiColor: .systemBackground), Color(uiColor: .secondarySystemBackground)],
                    startPoint: .top, endPoint: .bottom
                )
                if let accent = theme.accent {
                    LinearGradient(
                        colors: [accent.opacity(0.30), accent.opacity(0.05)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                }
            }
        } else {
            Color.clear
        }
    }
}

/// 調色掣：撳一下轉去下一個風格。
struct ThemeButton: View {
    @Environment(\.widgetTheme) private var theme

    var body: some View {
        Button(intent: ThemeIntent()) {
            Image(systemName: "paintpalette.fill")
                .foregroundStyle(theme.accent ?? .secondary)
        }
        .buttonStyle(.plain)
        .font(.system(size: 11))
    }
}

/// 「即時更新」掣，連上次更新時間。
struct RefreshButton: View {
    let updatedAt: Date

    var body: some View {
        Button(intent: RefreshIntent()) {
            HStack(spacing: 3) {
                Text(Formatting.clock(updatedAt)).monospacedDigit()
                Image(systemName: "arrow.clockwise")
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(.secondary)
    }
}

struct ProgressBar: View {
    @Environment(\.widgetRenderingMode) private var mode
    let fraction: Double
    let tint: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.25))
                Capsule()
                    .fill(mode == .fullColor ? tint : Color.primary)
                    .frame(width: max(0, min(1, fraction)) * geometry.size.width)
                    .widgetAccentable()
            }
        }
    }
}

/// 一格玻璃卡：Clear 模式用半透明白，完整彩色用系統填色。
struct GlassCard<Content: View>: View {
    @Environment(\.widgetRenderingMode) private var mode
    @Environment(\.widgetTheme) private var theme
    var tint: Color?
    var padding: CGFloat = 8
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
                if mode == .fullColor, let tint {
                    shape.fill(tint.opacity(0.16))
                } else if mode == .fullColor, let accent = theme.accent {
                    shape.fill(accent.opacity(0.14))
                } else if mode == .fullColor {
                    shape.fill(.fill.tertiary)
                } else {
                    shape.fill(Color.white.opacity(0.10))
                }
            }
    }
}

/// 細小標籤，例如組別、更類。
struct Badge: View {
    let text: String
    var color: Color = .secondary

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.18), in: Capsule())
            .widgetAccentable()
    }
}
