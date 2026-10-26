import Foundation
import WidgetKit

struct OverviewEntry: TimelineEntry {
    let date: Date
    let stats: SystemStats
    let battery: BatteryEstimate
    let info: ExtraInfo
    let schedule: ScheduleData
    let vps: VPSState
    let updatedAt: Date
    var batteryRate: Double? = nil
    var flips = FlipState()
    var theme = WidgetTheme.classic

    func isFlipped(_ id: String) -> Bool { flips.isFlipped(id, at: date) }

    var rebootHint: RebootHint { RebootHint.level(uptime: stats.uptime(at: date)) }
    var osStatus: OSVersionStatus { OSVersion.status(current: stats.systemVersion, latest: info.latestOS) }
    var batteryTone: BatteryTone { BatteryStyle.tone(level: stats.batteryLevel, charging: stats.isCharging) }
    var batterySymbol: String { BatteryStyle.symbol(level: stats.batteryLevel, charging: stats.isCharging) }

    /// 今日：00:00 換日；昨日夜更未放工就仍然係昨日（同 tml-roster 一致）。
    var serviceToday: String { Days.today(date) { schedule.duty(on: $0)?.off } }
    var serviceTomorrow: String { Days.add(serviceToday, 1) ?? serviceToday }
    var dutyToday: DutyDay? { schedule.duty(on: serviceToday) }
    var dutyTomorrow: DutyDay? { schedule.duty(on: serviceTomorrow) }

    private var todayStart: Date { ICalendar.hongKong.startOfDay(for: date) }
    var schoolToday: SchoolDay { schedule.school(dayStart: todayStart) }
    var schoolTomorrow: SchoolDay {
        schedule.school(dayStart: ICalendar.hongKong.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart)
    }

    /// 本週（服務日所在嘅星期一至日）概況；冇更表就 nil。
    var weekSummary: WeekSummary? {
        guard schedule.roster != nil, let monday = Days.mondayOf(serviceToday) else { return nil }
        let days = (0..<7).compactMap { Days.add(monday, $0).flatMap { schedule.duty(on: $0) } }
        return days.isEmpty ? nil : WeekSummary.make(days)
    }

    var nextHoliday: Holiday? { schedule.nextHoliday(dayStart: todayStart) }

    static var sample: OverviewEntry {
        let now = Date()
        let today = Days.serviceDate(now)
        let roster = Roster(
            rows: [Array(repeating: "1101157", count: 7)], numbers: [1], anchorRow: 1,
            anchorMonday: Days.mondayOf(today) ?? today, overrides: [Days.add(today, 1) ?? today: "RD"]
        )
        let dayStart = ICalendar.hongKong.startOfDay(for: now)
        var schedule = ScheduleData.empty
        schedule.roster = roster
        schedule.configured = true
        schedule.basic = ["1101157": DutyTime(on: 54_300, onPlace: "錦上路", off: 81_300, offPlace: "錦上路", hours: 7.5)]
        schedule.events = [
            CalendarEvent(title: "Day 4", start: dayStart, end: dayStart.addingTimeInterval(86_400), allDay: true, calendar: SchoolCalendars.cycleName, rule: nil),
            CalendarEvent(title: "中三家長會", start: dayStart.addingTimeInterval(19 * 3_600), end: dayStart.addingTimeInterval(20 * 3_600), allDay: false, calendar: "事項", rule: nil),
            CalendarEvent(title: "陸運會", start: dayStart.addingTimeInterval(86_400), end: dayStart.addingTimeInterval(2 * 86_400), allDay: true, calendar: "事項", rule: nil),
        ]
        return OverviewEntry(
            date: now, stats: .sample, battery: .remaining(5 * 3_600 + 20 * 60), info: .sample,
            schedule: schedule, vps: .sample, updatedAt: now
        )
    }
}
