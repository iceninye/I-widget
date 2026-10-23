import Foundation

enum BatteryTone: Equatable {
    case charging, normal, medium, low, unknown
}

/// 電池顏色同 SF Symbol。純函式，唔依賴 SwiftUI，方便單元測試。
enum BatteryStyle {
    static func tone(level: Double?, charging: Bool) -> BatteryTone {
        if charging { return .charging }
        guard let level else { return .unknown }
        if level <= 0.2 { return .low }
        return level <= 0.4 ? .medium : .normal
    }

    static func symbol(level: Double?, charging: Bool) -> String {
        if charging { return "battery.100percent.bolt" }
        guard let level else { return "battery.0percent" }
        let steps: [(Double, String)] = [(0.88, "100"), (0.63, "75"), (0.38, "50"), (0.13, "25")]
        for (threshold, name) in steps where level >= threshold {
            return "battery.\(name)percent"
        }
        return "battery.0percent"
    }
}
