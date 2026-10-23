import Foundation

/// 時鐘嘅 timeline 日期：每分鐘一個 entry，WidgetKit 會喺啱嘅一刻自動切換，
/// 唔使 reload（reload 先計預算，entry 唔計），所以時間永遠準確到分鐘。
enum ClockTimeline {
    /// 由 `start` 所屬分鐘嘅開頭起計，每分鐘一個日期。
    static func minuteDates(from start: Date, count: Int, calendar: Calendar = .current) -> [Date] {
        guard count > 0 else { return [] }
        let base = calendar.dateInterval(of: .minute, for: start)?.start ?? start
        return (0..<count).compactMap { calendar.date(byAdding: .minute, value: $0, to: base) }
    }

    /// 今日已過咗幾多（0...1）。
    static func dayProgress(_ date: Date, calendar: Calendar = .current) -> Double {
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return 0 }
        let span = end.timeIntervalSince(start)
        guard span > 0 else { return 0 }
        return min(max(date.timeIntervalSince(start) / span, 0), 1)
    }
}
