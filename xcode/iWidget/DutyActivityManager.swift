import ActivityKit
import Foundation

/// 更份倒數 Live Activity 嘅啟動、更新、結束。全部喺本機做（免費簽名冇推送 capability，
/// `pushType` 一定要留 `nil`，唔好加 push／entitlement），所以內容只會喺 app 開啟、
/// 捷徑執行或者「排交接提示」執行嗰陣更新；倒數數字由系統自己跳。
///
/// **所有改活動嘅操作都要排隊**：`sync` 係「先讀 `activities` 再決定 request／update」嘅
/// read-then-write，多個入口（`AppModel.rescheduleHandover`、設定頁手動掣、捷徑
/// 「更新更份倒數」／「排交接提示」）可以同一時間各自行一次。兩邊都見到空清單就會各
/// `Activity.request` 一個 → 鎖定畫面出現重複倒數（呢個並發窗口係實打實出過嘅事）。
/// 所以公開嘅 `sync`／`endAll` 一律經 `DutyActivityQueue`（actor）串行化，真正做事嘅係
/// `performSync`／`performEndAll`。
enum DutyActivityManager {
    /// 開 app／「排交接提示」執行時順手更新倒數
    static let enabledKey = "settings.dutyActivity"
    /// 下一件事前幾多分鐘先開始顯示
    static let leadKey = "settings.dutyActivityLead"
    /// 本 app 啟動倒數嗰一刻寫低嘅時間，用嚟計 6 小時輪替。
    /// **唔可以只靠佢**：`UserDefaults` 會因重裝／清資料而冇咗，到時舊活動會被當做啱啱先開始、一直更新落去。
    /// 所以 `sync` 另外用活動自己帶住嘅內容時間（`content.state.syncedAt`）做第二手基準，
    /// 見 `DutyActivityPlan.rotationBaseline`。ActivityKit 現行文件冇公開可靠嘅「活動開始時間」可用。
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
    /// 上網嗰段唔使排隊（只讀資料、唔改活動），真正改活動嗰一下先入隊；
    /// 呢度亦唔係喺 actor 入面回頭叫自己，所以唔會 deadlock。
    static func refresh(now: Date = Date()) async -> String {
        let token = AppSettings.string(AppSettings.rosterToken)
        guard RosterAPI.cleanToken(token) != nil else {
            return "未填 tml-roster token：開 i-widget →「設定」填一次。"
        }
        let data = await ScheduleData.load(token: token, now: now)
        return await sync(events: data.dutyEvents(now: now), now: now)
    }

    /// 按事件列表啟動／更新／結束。回傳一句話俾捷徑或者設定頁顯示。串行化見上面嘅說明。
    @discardableResult
    static func sync(events: [DutyEvent], now: Date = Date()) async -> String {
        await DutyActivityQueue.shared.sync(events: events, now: now)
    }

    /// 結束全部活動（同上，排喺同一條隊：唔可以喺 `sync` 讀完清單未改完之間插入）。
    static func endAll() async {
        await DutyActivityQueue.shared.endAll()
    }

    /// 真正做事嘅部分：只可以由 `DutyActivityQueue` 入面叫，唔好喺隊外面直接調用。
    fileprivate static func performSync(events: [DutyEvent], now: Date) async -> String {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return "Live Activity 未開：iPhone 設定 → i-widget →「即時動態」開啟。"
        }
        let running = Activity<DutyActivityAttributes>.activities
        let stored = UserDefaults.standard.object(forKey: startedKey) as? Date
        // 活動隨身帶住嘅內容生成時間：唔靠 UserDefaults 都計得到個活動幾舊（冇行緊就冇得計）。
        // 多過一個活動行緊時要攞**最舊**嗰個，唔可以攞清單第一個（見 `DutyActivityPlan.oldestContentAt`）。
        let contentAt = DutyActivityPlan.oldestContentAt(running.map { $0.content.state.syncedAt }, now: now)
        // 基準唔係純粹讀返嘅 `stored`：如果佢消失咗（或者內容比佢更舊），要把計低嘅時間補寫／修正返，
        // 下次先至有同一個基準可以用。呢步就係「running 但 startedAt 冇咗」嘅保守處理。
        let baseline = DutyActivityPlan.rotationBaseline(startedAt: stored, contentAt: contentAt, now: now)
        if !running.isEmpty, stored != baseline { UserDefaults.standard.set(baseline, forKey: startedKey) }
        let action = DutyActivityPlan.decide(
            events: events, now: now, running: !running.isEmpty,
            startedAt: stored, contentAt: contentAt, leadMinutes: leadMinutes
        )
        switch action {
        case .wait:
            return "未到時間：下一件事前 \(Self.windowText(leadMinutes))先開始顯示倒數。"
        case .end:
            await performEndAll()
            return "下一件事隔超過 \(Self.windowText(leadMinutes))（或者冇咗），已結束倒數；進入範圍會重新開始。"
        case .update(let state):
            let content = ActivityContent(state: state, staleDate: state.at)
            // 正常只有一個；多過一個（並發時期開出嘅重複倒數）就留**最舊**嗰個繼續做基準、收返其餘。
            // 留低嗰個一定要附上最終 content，唔可以 `end(nil)` 清狀態。
            let sorted = running.sorted { $0.content.state.syncedAt < $1.content.state.syncedAt }
            if let keep = sorted.first { await keep.update(content) }
            for activity in sorted.dropFirst() {
                await activity.end(activity.content, dismissalPolicy: .immediate)
            }
            return "已更新倒數：\(state.action) \(Formatting.clock(state.at))"
        case .start(let state):
            // 先成功建立新活動，先至收返舊嘅：倒轉（endAll → request）會喺 request 失敗時兩頭空。
            // `pushType: nil` 一定要保留：免費簽名冇推送 capability，加咗會即刻失敗。
            let created: Activity<DutyActivityAttributes>
            do {
                created = try Activity.request(
                    attributes: DutyActivityAttributes(),
                    content: ActivityContent(state: state, staleDate: state.at),
                    pushType: nil
                )
            } catch {
                let kept = running.isEmpty ? "" : "，保留原本嘅倒數"
                return "開始唔到倒數\(kept)：\(error.localizedDescription)"
            }
            // `running` 係 request 之前讀嘅，唔計啱啱開出嗰個；重讀一次清單先係真實狀態：
            // 除咗成功開出嗰個，其餘（包括之前並發窗口可能開出嘅重複）一律收掉。
            for activity in Activity<DutyActivityAttributes>.activities where activity.id != created.id {
                await activity.end(activity.content, dismissalPolicy: .immediate)
            }
            UserDefaults.standard.set(now, forKey: startedKey)
            return "已開始倒數：\(state.action) \(Formatting.clock(state.at))"
        }
    }

    /// 真正結束全部活動：附上各活動最後嘅 content（`end(nil)` 會清走狀態，鎖定畫面會閃空白／變返預設）。
    fileprivate static func performEndAll() async {
        for activity in Activity<DutyActivityAttributes>.activities {
            await activity.end(activity.content, dismissalPolicy: .immediate)
        }
        UserDefaults.standard.removeObject(forKey: startedKey)
    }
}

/// 將「改 Live Activity」嘅操作排一條隊（Swift 5 語言模式都用到 `actor`，iOS 17 無問題）。
///
/// 冇佢就等於「讀清單 → 決定 → request／end」之間可以俾第二個入口插入：兩邊都見到空清單，
/// 各 request 一個，鎖定畫面就出現兩個倒數。串行化之後重複活動先至唔會再開出；
/// 萬一舊版已經留低咗幾個，`performSync` 會留最舊嗰個、收掉其餘（基準都係按最舊嗰個計）。
///
/// 唔會 deadlock：呢度入面只叫 `DutyActivityManager.performSync`／`performEndAll`
/// （非隔離、淨係掂 ActivityKit 同 `UserDefaults`），唔會回叫公開嘅 `sync`／`endAll`，
/// 亦唔會等 main actor。排隊嘅代價只係「最長要等前面一輪改完」，呢啲操作本身好短
/// （唔包上網——`refresh` 嘅上網段喺隊外面先做），用家同捷徑只會見到慢一步，唔會見到兩個倒數。
private actor DutyActivityQueue {
    static let shared = DutyActivityQueue()

    func sync(events: [DutyEvent], now: Date) async -> String {
        await DutyActivityManager.performSync(events: events, now: now)
    }

    func endAll() async {
        await DutyActivityManager.performEndAll()
    }
}
