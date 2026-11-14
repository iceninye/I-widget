import Foundation

/// kind →  Live Activity 主行顯示嘅動作名。
/// 主行只係一個短詞，渲染先唔使再拆 `title`，亦唔會同 `note` 重複。
enum DutyAction {
    static let fallback = "更份"

    /// `kind` 係 `HandoverAlert.Kind.rawValue`（Live Activity 內容要 Codable，所以用字串）。
    /// 認唔到（舊版殘留、缺欄位、空字串）就靠 `Kind(rawValue:)` 回傳 `nil` 跌落 `fallback`。
    /// 呢度唔寫 `default`：`Kind` 加咗新 case 時編譯器會逼你補名，唔會靜靜咁當佢「更份」。
    static func name(_ kind: String) -> String {
        guard let value = HandoverAlert.Kind(rawValue: kind) else { return fallback }
        switch value {
        case .on: return "返工"
        case .pickUp: return "接車"
        case .dropOff: return "落地"
        case .off: return "放工"
        }
    }
}

/// 更份入面一件「事」：返工、接車、落地、放工，同佢發生嘅時間。
/// 同提示（`HandoverAlert`）用同一套資料，但唔受「提前幾耐提」影響（設咗唔提都要倒數）。
struct DutyEvent: Equatable {
    var kind: HandoverAlert.Kind
    var at: Date
    /// 完整一句，例如「落地 10:42 · 錦上路 2」。通知／日誌用；Live Activity 渲染唔再靠佢。
    var title: String
    /// `body` 去走「N 分鐘後」嘅成句，例如「喺錦上路 2落地，接你嗰位係 118 更，之後用膳到 11:16」。
    var detail: String
    /// 事件地點，例如「錦上路 2」
    var place: String
    /// 補充資料（Run、交接對象、目的地、之後做咩），唔重複 `title` 嘅動作、時間、地點
    var note: String

    /// 主行顯示嘅動作名
    var action: String { DutyAction.name(kind.rawValue) }

    init(kind: HandoverAlert.Kind, at: Date, title: String, detail: String, place: String = "", note: String = "") {
        self.kind = kind
        self.at = at
        self.title = title
        self.detail = detail
        self.place = place
        self.note = note
    }

    init(_ alert: HandoverAlert) {
        self.init(
            kind: alert.kind, at: alert.eventAt, title: alert.title, detail: alert.detail,
            place: alert.place, note: alert.note
        )
    }

    /// 全部提示合併成事件：同一件事（例如上班前 1 小時同 15 分鐘兩個提示）只留一個，按時間排序，只留仲未發生嘅。
    /// `eventAt` 係實際時間，所以過咗午夜（服務日 seconds > 86400）都會排喺同一日之後。
    static func upcoming(from alerts: [HandoverAlert], now: Date) -> [DutyEvent] {
        var seen = Set<String>()
        return alerts
            .filter { $0.eventAt > now }
            .sorted { $0.eventAt < $1.eventAt }
            .filter { seen.insert("\($0.kind.rawValue)|\($0.eventAt.timeIntervalSince1970)|\($0.title)").inserted }
            .map(DutyEvent.init)
    }
}

/// 之後嘅事：要帶埋時間，渲染時先可以判斷有冇過期（過期嘅唔應該再當「即將發生」）。
struct DutyLaterItem: Codable, Hashable, Identifiable {
    var kind: String
    var at: Date
    var place: String
    var note: String

    /// 同一件事（同一 kind + 同一時間）就係同一行
    var id: String { "\(kind)-\(Int(at.timeIntervalSince1970.rounded()))" }
    var action: String { DutyAction.name(kind) }

    init(kind: String, at: Date, place: String = "", note: String = "") {
        self.kind = kind
        self.at = at
        self.place = place
        self.note = note
    }

    init(_ event: DutyEvent) {
        self.init(kind: event.kind.rawValue, at: event.at, place: event.place, note: event.note)
    }
}

/// Live Activity 顯示嘅內容：下一件事（動作、時間、地點、補充）加之後最多兩個。
/// 倒數數字由系統自己跳（`Text(timerInterval:)`），所以唔使不斷更新。
struct DutyActivityState: Codable, Hashable {
    var kind: String
    var at: Date
    var place: String
    var note: String
    /// 下一件事之後嘅事（有限數量，帶時間）。渲染嗰一刻先過濾已過期嘅，唔係系統自己收行。
    var later: [DutyLaterItem]
    /// 呢份內容幾時砌出（內容生成時間）。
    /// 留意：「待更新」唔係靠佢倒數——系統只喺 `ActivityContent.staleDate`（即主事件 `at`）過咗之後
    /// 將 `isStale` 變 true。呢度留低係俾無障礙描述講出內容幾時生成，同俾 app 計活動年齡（輪替用）。
    var syncedAt: Date

    var action: String { DutyAction.name(kind) }

    init(kind: String, at: Date, place: String, note: String, later: [DutyLaterItem], syncedAt: Date) {
        self.kind = kind
        self.at = at
        self.place = place
        self.note = note
        self.later = later
        self.syncedAt = syncedAt
    }

    /// 舊版內容（得 `kind`/`title`/`detail`/`at`/`later: [String]`）都要照讀得到：
    /// 更新 app 時鎖定畫面可能有舊格式嘅活動未收，讀取失敗會令渲染同 `endAll()` 出事。
    /// 缺欄位就用預設值（無地點、無補充、無之後），`encode(to:)` 照由編譯器合成。
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        kind = (try? values.decode(String.self, forKey: .kind)) ?? ""
        at = (try? values.decode(Date.self, forKey: .at)) ?? Date(timeIntervalSince1970: 0)
        place = (try? values.decode(String.self, forKey: .place)) ?? ""
        note = (try? values.decode(String.self, forKey: .note)) ?? ""
        later = (try? values.decode([DutyLaterItem].self, forKey: .later)) ?? []
        syncedAt = (try? values.decode(Date.self, forKey: .syncedAt)) ?? at
    }

    /// 主事件已過時間（系統過咗 `staleDate` 都係同一件事：真正兜底就係呢個時間）
    func isPast(now: Date) -> Bool { at <= now }

    /// 「之後」嘅事喺**渲染嗰一刻**用 `now` 過濾掉已過期嘅。
    /// 注意：Live Activity 唔會自己重畫，所以呢個只係展示層嘅過濾，唔係自動過期機制；
    /// 過咗頭嘅真正兜底係主事件 `staleDate`（`isStale` → 成個畫面轉「待更新」）。
    func upcomingLater(now: Date) -> [DutyLaterItem] { later.filter { $0.at > now } }

    /// 無障礙讀出：動作、時刻、地點、狀態
    func accessibilityText(now: Date, stale: Bool) -> String {
        var parts: [String]
        if stale || isPast(now: now) {
            parts = ["待更新，上次事件 \(Formatting.clock(at)) \(action)"]
            if !place.isEmpty { parts.append(place) }
            // 內容生成時間（`syncedAt`）：講明呢份資料係幾時砌嘅，等用家知「待更新」係咪好舊。
            // 呢欄唔驅動「待更新」本身，只係描述內容新舊；缺欄位嘅舊內容會跌落 `at`。
            parts.append("內容建於 \(Formatting.clock(syncedAt))")
        } else {
            parts = ["下一件事 \(Formatting.clock(at)) \(action)"]
            if !place.isEmpty { parts.append(place) }
            if !note.isEmpty { parts.append(note) }
            let upcoming = upcomingLater(now: now)
            if !upcoming.isEmpty {
                parts.append("之後 " + upcoming.map { "\($0.action) \(Formatting.clock($0.at))" }.joined(separator: "、"))
            }
        }
        return parts.joined(separator: "，")
    }
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

    /// 本 app 主動輪替嘅門檻：由輪替基準（見 `rotationBaseline`）計起行咗 6 小時就收返、開新嘅。
    /// iOS 系統上限係 8 小時（超過會強制結束活動、內容唔再更新），所以企喺 6 小時重開，
    /// 留返兩小時俾更新失敗、無網絡同用家唔開 app 嘅情況。
    static let maxAge: TimeInterval = 6 * 3_600
    static let defaultLeadMinutes = 180

    /// `later` 清單最多幾個（版面 + 4 KB 上限）
    static let maxLaterItems = 2
    /// Live Activity content 編碼後嘅硬上限：超過 `Activity.request` / `update` 會失敗。
    static let contentByteLimit = 4_096
    /// 每個地點／補充資料嘅字數上限（中文字 JSON 編碼後最多 6 字節一個）
    static let maxPlaceCharacters = 40
    static let maxNoteCharacters = 120

    static func state(events: [DutyEvent], now: Date) -> DutyActivityState? {
        let upcoming = events.filter { $0.at > now }.sorted { $0.at < $1.at }
        guard let next = upcoming.first else { return nil }
        return limited(DutyActivityState(
            kind: next.kind.rawValue,
            at: next.at,
            place: next.place,
            note: next.note,
            later: upcoming.dropFirst().prefix(Self.maxLaterItems).map { DutyLaterItem($0) },
            syncedAt: now
        ))
    }

    /// 編碼後嘅位元組數（`JSONEncoder` 失敗當超大，等 `limited` 去縮）。
    static func byteCount(_ state: DutyActivityState) -> Int {
        guard let data = try? JSONEncoder().encode(state) else { return .max }
        return data.count
    }

    /// 4 KB 保護：限 `later` 數量同字數；仲超就折半縮，確保編碼後 ≤ `contentByteLimit`。
    static func limited(_ state: DutyActivityState) -> DutyActivityState {
        var result = trimmed(state, place: maxPlaceCharacters, note: maxNoteCharacters)
        result.later = Array(result.later.prefix(maxLaterItems))
        // 折半一定收斂：字縮到空、later 削到冇，剩低嘅骨架遠低於 4 KB。
        var rounds = 0
        while byteCount(result) > contentByteLimit, rounds < 10 {
            rounds += 1
            result = trimmed(result, place: result.place.count / 2, note: result.note.count / 2)
            if result.place.isEmpty, result.note.isEmpty, !result.later.isEmpty { result.later.removeLast() }
        }
        return result
    }

    private static func trimmed(_ state: DutyActivityState, place: Int, note: Int) -> DutyActivityState {
        var result = state
        result.place = String(result.place.prefix(max(place, 0)))
        result.note = String(result.note.prefix(max(note, 0)))
        result.later = result.later.map {
            DutyLaterItem(kind: $0.kind, at: $0.at, place: String($0.place.prefix(max(place, 0))), note: String($0.note.prefix(max(note, 0))))
        }
        return result
    }

    /// 事件邊界最多取幾個（同 widget timeline 一樣唔使排到十幾個鐘之後）。
    static let maxTimelineBoundaries = 8

    /// 「幾時值得再睇一次資料」嘅時刻：每個事件時間 + 1 秒，只計仲未發生嘅，按時間升序，最多 `maxTimelineBoundaries` 個。
    /// 加 1 秒係要跨過嗰一刻先醒：倒數同「下一件事」要由舊事件轉去對下一件（`Overview` widget timeline 同
    /// app 前景輪循都用呢個取法，避免兩邊各寫一次）。醒咗唔代表一定有新嘢，冇網絡就用快取。
    static func boundaries(events: [DutyEvent], now: Date) -> [Date] {
        events.filter { $0.at > now }.sorted { $0.at < $1.at }
            .prefix(maxTimelineBoundaries).map { $0.at.addingTimeInterval(1) }
    }

    /// 輪替基準：攞 `startedAt`（app 自己喺 `UserDefaults` 記低嘅啟動時間）同
    /// `contentAt`（活動隨身帶住嘅內容生成時間 `content.state.syncedAt`）之中**較舊**嗰個；
    /// 兩個都冇（第一次見到個活動、舊內容又冇時間欄位）就用 `now`。
    /// 遲過 `now` 嘅候選一律唔當基準（舊內容缺 `syncedAt` 會跌落主事件時間，而主事件可能仲未發生；
    /// 用佢做基準會令輪替一直推後），當唔到基準就當而家開始。
    ///
    /// 點解唔單靠 `UserDefaults`：呢個紀錄隨時可以冇（重裝、清資料、換機），一旦冇咗又當個活動啱啱開始，
    /// 舊倒數就會一直更新落去。內容時間由系統連活動一齊存，所以：
    /// - 正常（有 `startedAt`）：照喺真正啟動時間 + 6 小時輪替；更新內容唔會推後呢個時間（因為攞較舊嗰個）。
    /// - `startedAt` 冇咗：用內容時間做基準，個活動最遲「最後一次更新 + 6 小時」就輪替。
    /// - 兩樣都冇：基準補寫成 `now`（`DutyActivityManager` 會寫返落 `UserDefaults`），
    ///   即首次見到嘅舊活動最長再多行 6 小時先重開——呢個係「首次重建基準」嘅限制，
    ///   ActivityKit 現行文件冇公開可靠嘅「活動開始時間」欄位可用（`date`／`activeStartDate` 都搵唔到），
    ///   唔敢憑空用。保底系統自己嘅 8 小時硬上限會殺咗活動，下一次 `sync` 重新 request，唔會無限長駐。
    static func rotationBaseline(startedAt: Date?, contentAt: Date?, now: Date) -> Date {
        [startedAt, contentAt]
            .compactMap { $0 }
            .filter { $0 <= now }
            .min() ?? now
    }

    /// - Parameters:
    ///   - running: 而家有冇 Live Activity 行緊
    ///   - startedAt: app 記低嘅啟動時間（用嚟避開系統 8 小時上限）；可能已經喺 `UserDefaults` 消失
    ///   - contentAt: 活動帶住嘅內容生成時間（`activity.content.state.syncedAt`），冇行緊就 `nil`
    ///   - leadMinutes: 下一件事前幾多分鐘先開始顯示
    static func decide(
        events: [DutyEvent], now: Date, running: Bool, startedAt: Date?, contentAt: Date? = nil, leadMinutes: Int
    ) -> Action {
        guard let next = state(events: events, now: now) else { return running ? .end : .wait }
        let horizon = TimeInterval(max(leadMinutes, 0) * 60)
        // 超出可預見範圍：唔好長駐十幾個鐘後先發生嘅倒數（睇落似有嘢做，其實唔係）。
        // 行緊就結束，等下一次進入窗口先重新啟動。
        if next.at.timeIntervalSince(now) > horizon { return running ? .end : .wait }
        if running {
            let baseline = rotationBaseline(startedAt: startedAt, contentAt: contentAt, now: now)
            if now.timeIntervalSince(baseline) > maxAge { return .start(next) }
            return .update(next)
        }
        return .start(next)
    }
}
