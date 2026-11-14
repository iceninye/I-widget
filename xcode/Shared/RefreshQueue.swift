import Foundation

/// app「開一輪刷新」嘅純決策：邊個即刻跑、邊個排隊、跑完要唔要補跑，
/// 同埋唔喺「資料頁 + 前景」期間跨過咗事件邊界，返嚟之後點算。
///
/// 呢度唔碰網絡、唔碰 SwiftUI、亦唔自己讀 `Date()`（時間一律由呼叫者傳入），所以規則可以喺
/// `iWidgetTests` 逐個情境測（見 `RefreshQueueTests`）；`ContentView` 只負責將決定落到 `@State`，
/// 唔喺 View 內重寫規則：規則改動要喺呢度睇到，唔可以 View 一套、測試另一套。
///
/// 事件邊界本身點取（只收未來、+1 秒、最多 8 個）仍然只係 `DutyActivityPlan.boundaries` 嘅責任，
/// 呢度唔重複一次。
enum RefreshQueue {

    /// 一個刷新請求進入時點做。
    ///
    /// 「一定要做到」嘅請求（deep link、返前景、跨過事件邊界、設定改完 token）喺有輪跑緊時
    /// 會被 `loading` guard 默默吞咗，就等於用戶改嘅最後幾個字、或者撳 Live Activity 入嚟嗰次
    /// 更新永遠做唔到；所以呢類要排返隊補跑（`.enqueue`），而「順手」請求（低耗電模式改變、
    /// 冷啟）就併入跑緊嗰輪（`.merge`），唔會一輪接一輪打網。
    enum Accept: Equatable {
        /// 冇人跑緊：即刻開一輪
        case start
        /// 有輪跑緊，而且呢次一定要做到：記低佢，等嗰輪完咗補跑
        case enqueue
        /// 有輪跑緊，呢次純粹順手：當嗰輪已經包底，唔使多做
        case merge
    }

    static func accept(refreshing: Bool, mustRefresh: Bool) -> Accept {
        guard refreshing else { return .start }
        return mustRefresh ? .enqueue : .merge
    }

    /// 名單之中最舊嗰個邊界係咪已經跨過（名單空 → 冇嘢可跨，唔算跨過）。
    /// 用 `>=`：邊界本身已經係「事件時間 + 1 秒」，到正嗰一刻就應該醒。
    static func crossed(_ boundaries: [Date], now: Date) -> Bool {
        guard let first = boundaries.first else { return false }
        return now >= first
    }

    /// 一輪跑完之後，要唔要即刻再跑多一輪。
    /// - Parameter pending: 輪跑完之前又有「一定要做到」嘅請求入咗隊。
    /// - Parameter overshot: 本輪期間跨過咗一個邊界——重排只收未來事件，嗰個邊界會被剔除，
    ///   唔補跑就**永久**冇人補（鎖定畫面嘅「下一件事」同倒數會一直留低舊內容，
    ///   要等到下一個邊界先醒，可能係幾個鐘之後）。
    /// 兩者都要多跑一輪；每次多跑都一定用掉一個真實嘅跨過或者一個真實嘅排隊請求，
    /// 所以呢個循環會收斂，唔會變成無限打網。
    static func followUp(pending: Bool, overshot: Bool) -> Bool { pending || overshot }

    /// 前景心跳（`tick`）嘅決定。只喺「資料」分頁 + 前景先值得監視事件邊界，
    /// 其他情況會清掉名單（唔好繼續用住舊事件）。
    ///
    /// 清名單就係問題所在：如果跨過恰好發生喺離開期間，清咗之後返嚟重新排只收未來事件，
    /// 嗰次跨過就永久丟失。所以離開時要先 latch（`pause(missed:)`），返嚟時補跑（`.catchUp`）。
    enum Tick: Equatable {
        /// 離開監視：清名單。`missed` = 清之前已經有邊界跨過咗，要記低，返嚟補跑。
        case pause(missed: Bool)
        /// 返到「資料頁 + 前景」而且之前記低咗遺漏：補跑一次（名單由補跑嗰輪照最新資料重排）。
        case catchUp
        /// 繼續監視：`crossed` = 呢一刻已經跨過名單最舊嗰個邊界，要 refresh。
        case rearm(crossed: Bool)
    }

    static func tick(dataTab: Bool, active: Bool, boundaries: [Date], missed: Bool, now: Date) -> Tick {
        guard dataTab, active else { return .pause(missed: missed || crossed(boundaries, now: now)) }
        // 遺漏只補一次：補跑嗰輪完成時會重排名單，之後照正常監視行
        if missed { return .catchUp }
        return .rearm(crossed: crossed(boundaries, now: now))
    }

    /// 設定頁三個 token 輸入框嘅 debounce 決定。
    ///
    /// 逐個字都打網會一輪接一輪（而且跑緊嗰輪讀嘅係輪開始時嘅舊 token，最後嗰幾個字永遠輸唔入去）；
    /// 所以要停手 `settingsDebounceNanos` 先發，並且用 `mustRefresh: true` 發（見 `Accept`）。
    /// 三個框合成一個 key 傳入：任何一格改過都算「改過」。
    enum TokenEdit: Equatable {
        /// 首次見到呢個值（入頁、或者 app 重開）：唔算用家改嘢，唔使打網
        case firstSeen
        /// 同上次觸發時一樣：唔使多打一次網
        case unchanged
        /// 改過：等咗 debounce 之後觸發一次（取消就唔算，最新嗰次輸入先會發）
        case fire
    }

    /// 停手幾耐算「打完」：500 毫秒。細到用家覺得係即時，大到唔會逐個字打網。
    static let settingsDebounceNanos: UInt64 = 500_000_000

    static func tokenEdit(current: String, lastFired: String?) -> TokenEdit {
        guard let lastFired else { return .firstSeen }
        return current == lastFired ? .unchanged : .fire
    }
}
