import Foundation

/// 更份入面一件「事」：返工、接車、落地、放工，同佢發生嘅時間。
/// 同提示（`HandoverAlert`）用同一套資料，但唔受「提前幾耐提」影響（設咗唔提都要倒數）。
struct DutyEvent: Equatable {
    var kind: HandoverAlert.Kind
    var at: Date
    /// 例如「落地 10:42 · 錦上路 2」
    var title: String
    /// 例如「喺錦上路 2落地，接你嗰位係 118 更，之後用膳到 11:16」
    var detail: String

    init(kind: HandoverAlert.Kind, at: Date, title: String, detail: String) {
        self.kind = kind
        self.at = at
        self.title = title
        self.detail = detail
    }

    init(_ alert: HandoverAlert) {
        self.init(kind: alert.kind, at: alert.eventAt, title: alert.title, detail: alert.detail)
    }

    /// 全部提示合併成事件：同一件事（例如上班前 1 小時同 15 分鐘兩個提示）只留一個，按時間排序，只留仲未發生嘅。
    static func upcoming(from alerts: [HandoverAlert], now: Date) -> [DutyEvent] {
        var seen = Set<String>()
        return alerts
            .filter { $0.eventAt > now }
            .sorted { $0.eventAt < $1.eventAt }
            .filter { seen.insert("\($0.kind.rawValue)|\($0.eventAt.timeIntervalSince1970)|\($0.title)").inserted }
            .map(DutyEvent.init)
    }
}

/// Live Activity 顯示嘅內容：下一件事同倒數，加之後兩件事。
/// 倒數數字由系統自己跳（`Text(timerInterval:)`），所以唔使不斷更新。
struct DutyActivityState: Codable, Hashable {
    var kind: String
    var title: String
    var detail: String
    var at: Date
    /// 下一件事之後嘅兩件事（標題，已含時間）
    var later: [String]
}

/// 決定 Live Activity 要做咩：等、啟動、更新，定係結束。純邏輯，唔掂 ActivityKit，方便測試。
enum DutyActivityPlan {
    enum Action: Equatable {
        /// 未到時間（或者冇嘢可做）
        case wait
        case start(DutyActivityState)
        case update(DutyActivityState)
        case end
    }

    /// Live Activity 最長 8 小時；行咗超過呢段時間就結束舊嘅、開新嘅。
    static let maxAge: TimeInterval = 6 * 3_600
    static let defaultLeadMinutes = 180

    static func state(events: [DutyEvent], now: Date) -> DutyActivityState? {
        let upcoming = events.filter { $0.at > now }.sorted { $0.at < $1.at }
        guard let next = upcoming.first else { return nil }
        return DutyActivityState(
            kind: next.kind.rawValue,
            title: next.title,
            detail: next.detail,
            at: next.at,
            later: upcoming.dropFirst().prefix(2).map(\.title)
        )
    }

    /// - Parameters:
    ///   - running: 而家有冇 Live Activity 行緊
    ///   - startedAt: 呢個 Live Activity 幾時開始（用嚟避開 8 小時上限）
    ///   - leadMinutes: 下一件事前幾多分鐘先開始顯示
    static func decide(events: [DutyEvent], now: Date, running: Bool, startedAt: Date?, leadMinutes: Int) -> Action {
        guard let next = Self.state(events: events, now: now) else { return running ? .end : .wait }
        if running {
            if let startedAt, now.timeIntervalSince(startedAt) > maxAge { return .start(next) }
            return .update(next)
        }
        return next.at.timeIntervalSince(now) > Double(max(leadMinutes, 0)) * 60 ? .wait : .start(next)
    }
}
