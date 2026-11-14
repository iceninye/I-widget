import Foundation
import WidgetKit

/// 邊個 widget 計邊啲來源：兩個 widget 喺同一個 extension 入面共用同一份快取，
/// 所以「更新於」一定要按來源分，否則會互相用對方啱啱成功嘅時間灌水。
enum OverviewPart {
    /// 今日咭：更份（roster／duties／dutySheets／dutyCards／places）、學校日曆、天氣、天氣警告、屯馬綫。
    case today
    /// 各項資訊：天氣、天氣警告、屯馬綫、黃金、空氣、匯率、最新系統版本、VPS。
    case info
}

/// 一個畫面嘅資料。三個時間語意分開：
/// - `date`：呢個 entry（畫面）嘅產生／生效時間，倒數同進度以佢為準。
/// - `updatedAt`：最後**任一相關來源**成功取得嘅時間（唔係「全部來源都成功」，來源範圍見 `OverviewPart`）；
///   冇任何成功記錄就 nil（顯示「未有資料」，唔好假裝啱啱更新）。
/// - `DataCache` 嘅 `dataAt`：最後*嘗試*讀取嘅時間（由 provider 喺每次上網時寫）。
struct OverviewEntry: TimelineEntry {
    let date: Date
    let stats: SystemStats
    let battery: BatteryEstimate
    let info: ExtraInfo
    let schedule: ScheduleData
    let vps: VPSState
    let updatedAt: Date?
    var batteryRate: Double? = nil
    var flips = FlipState()
    var theme = WidgetTheme.classic

    /// 全 app 口徑（app 內預覽用）：所有來源 — 資訊各項、更份／學校日曆、VPS — 最後**任一**成功嘅時間；
    /// 一個來源嘅成功時間都冇先 nil。注意係「任一」唔係「全部」。
    static func lastSuccess(info: ExtraInfo, schedule: ScheduleData) -> Date? {
        [info.updatedAt, schedule.lastSuccessAt, DataCache.savedAt("vps")].compactMap { $0 }.max()
    }

    /// widget 標題「更新於」：只計該 widget 會畫嘅來源，取最後**任一**成功嘅時間。
    /// 今日咭唔計黃金／空氣／匯率／最新版本／VPS；資訊 widget 唔計更份／學校日曆。
    /// 冇任何相關來源成功過就 nil（顯示「未有資料」）。
    static func lastSuccess(info: ExtraInfo, schedule: ScheduleData, part: OverviewPart) -> Date? {
        switch part {
        case .today: return [info.todayUpdatedAt, schedule.lastSuccessAt].compactMap { $0 }.max()
        case .info: return [info.infoUpdatedAt, DataCache.savedAt("vps")].compactMap { $0 }.max()
        }
    }

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
