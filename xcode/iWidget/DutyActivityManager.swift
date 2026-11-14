import ActivityKit
import Foundation

/// 更份倒數 Live Activity 嘅啟動、更新、結束。全部喺本機做（免費簽名冇推送 capability，
/// `pushType` 一定要留 `nil`，唔好加 push／entitlement），所以內容只會喺 app 開啟、
/// 捷徑執行或者「排交接提示」執行嗰陣更新；倒數數字由系統自己跳。
enum DutyActivityManager {
    /// 開 app／「排交接提示」執行時順手更新倒數
    static let enabledKey = "settings.dutyActivity"
    /// 下一件事前幾多分鐘先開始顯示
    static let leadKey = "settings.dutyActivityLead"
    private static let startedKey = "dutyActivity.startedAt"

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    static var leadMinutes: Int {
        let value = UserDefaults.standard.integer(forKey: leadKey)
        return value > 0 ? value : DutyActivityPlan.defaultLeadMinutes
    }

    /// 俾用家睇嘅提前窗口：足一小時就講「3 小時」，否則講分鐘（唔好講「0 小時」）。
    private static func windowText(_ minutes: Int) -> String {
        minutes >= 60 && minutes % 60 == 0 ? "\(minutes / 60) 小時" : "\(minutes) 分鐘"
    }

    static var isRunning: Bool { !Activity<DutyActivityAttributes>.activities.isEmpty }

    /// 讀返更份（要網絡）再同步 Live Activity。捷徑動作用。
    static func refresh(now: Date = Date()) async -> String {
        let token = AppSettings.string(AppSettings.rosterToken)
        guard RosterAPI.cleanToken(token) != nil else {
            return "未填 tml-roster token：開 i-widget →「設定」填一次。"
        }
        let data = await ScheduleData.load(token: token, now: now)
        return await sync(events: data.dutyEvents(now: now), now: now)
    }

    /// 按事件列表啟動／更新／結束。回傳一句話俾捷徑或者設定頁顯示。
    @discardableResult
    static func sync(events: [DutyEvent], now: Date = Date()) async -> String {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return "Live Activity 未開：iPhone 設定 → i-widget →「即時動態」開啟。"
        }
        let running = Activity<DutyActivityAttributes>.activities
        let started = UserDefaults.standard.object(forKey: startedKey) as? Date
        let action = DutyActivityPlan.decide(
            events: events, now: now, running: !running.isEmpty, startedAt: started, leadMinutes: leadMinutes
        )
        switch action {
        case .wait:
            return "未到時間：下一件事前 \(Self.windowText(leadMinutes))先開始顯示倒數。"
        case .end:
            await endAll()
            return "下一件事隔超過 \(Self.windowText(leadMinutes))（或者冇咗），已結束倒數；進入範圍會重新開始。"
        case .update(let state):
            let content = ActivityContent(state: state, staleDate: state.at)
            for (index, activity) in running.enumerated() {
                // 正常只有一個；多過一個就更新第一個、收返其餘（附上最終 content，唔好清空）
                if index == 0 { await activity.update(content) } else { await activity.end(activity.content, dismissalPolicy: .immediate) }
            }
            return "已更新倒數：\(state.action) \(Formatting.clock(state.at))"
        case .start(let state):
            // 先成功建立新活動，先至收返舊嘅：倒轉（endAll → request）會喺 request 失敗時兩頭空。
            do {
                _ = try Activity.request(
                    attributes: DutyActivityAttributes(),
                    content: ActivityContent(state: state, staleDate: state.at),
                    pushType: nil
                )
            } catch {
                let kept = running.isEmpty ? "" : "，保留原本嘅倒數"
                return "開始唔到倒數\(kept)：\(error.localizedDescription)"
            }
            // `running` 係 request 之前讀嘅，新活動唔會喺入面
            for activity in running { await activity.end(activity.content, dismissalPolicy: .immediate) }
            UserDefaults.standard.set(now, forKey: startedKey)
            return "已開始倒數：\(state.action) \(Formatting.clock(state.at))"
        }
    }

    /// 結束全部活動：附上各活動最後嘅 content（`end(nil)` 會清走狀態，鎖定畫面會閃空白／變返預設）。
    static func endAll() async {
        for activity in Activity<DutyActivityAttributes>.activities {
            await activity.end(activity.content, dismissalPolicy: .immediate)
        }
        UserDefaults.standard.removeObject(forKey: startedKey)
    }
}
