import ActivityKit
import Foundation

/// 更份倒數 Live Activity 嘅啟動、更新、結束。全部喺本機做（免費簽名冇 push），
/// 所以內容只會喺 app 開啟、捷徑執行或者「排交接提示」執行嗰陣更新；倒數數字由系統自己跳。
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
            return "未到時間：下一件事前 \(leadMinutes / 60) 小時先開始顯示倒數。"
        case .end:
            await endAll()
            return "冇下一件事，已結束倒數。"
        case .update(let state):
            let content = ActivityContent(state: state, staleDate: state.at)
            for (index, activity) in running.enumerated() {
                if index == 0 { await activity.update(content) } else { await activity.end(nil, dismissalPolicy: .immediate) }
            }
            return "已更新倒數：\(state.title)"
        case .start(let state):
            await endAll()
            do {
                _ = try Activity.request(
                    attributes: DutyActivityAttributes(),
                    content: ActivityContent(state: state, staleDate: state.at),
                    pushType: nil
                )
                UserDefaults.standard.set(now, forKey: startedKey)
                return "已開始倒數：\(state.title)"
            } catch {
                return "開始唔到倒數：\(error.localizedDescription)"
            }
        }
    }

    static func endAll() async {
        for activity in Activity<DutyActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        UserDefaults.standard.removeObject(forKey: startedKey)
    }
}
