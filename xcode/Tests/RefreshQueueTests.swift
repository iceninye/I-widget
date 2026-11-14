import XCTest

/// `Shared/RefreshQueue.swift` 嘅純決策測試（對應審查發現 1／2／3／4）：
/// 1. 跑緊嗰時到嘅「一定要做到」請求唔會丟（排隊補跑）；
/// 2. 一輪跑緊期間跨過嘅事件邊界唔會俾重排默默剔除（要補跑一輪）；
/// 3. 唔喺前景／其他分頁時跨過嘅邊界，返嚟會補跑一次；
/// 4. 冇跨過就唔好打網。
final class RefreshQueueTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func at(_ seconds: TimeInterval) -> Date { now.addingTimeInterval(seconds) }

    /// 模擬 `SettingsView` 嗰個 debounce task：`cancelled` = 瞓緊嗰時又改咗字
    /// （`Task.isCancelled` → 直接 return，唔更新 `firedKey`、唔打網）。
    /// 回傳「呢次有冇真係觸發刷新」加新嘅 `firedKey`（View 入面嗰個 `@State`）。
    private func tokenTaskStep(current: String, firedKey: String?, cancelled: Bool) -> (fired: Bool, firedKey: String?) {
        switch RefreshQueue.tokenEdit(current: current, lastFired: firedKey) {
        case .firstSeen:
            return (false, current)
        case .unchanged:
            return (false, firedKey)
        case .fire:
            guard !cancelled else { return (false, firedKey) }
            return (true, current)
        }
    }

    // MARK: - 發現 1：跑緊時新請求唔會丟

    /// 冇人跑緊就即刻跑；跑緊嗰時「一定要做到」要排隊，只有「順手」請求先可以併入而家嗰輪。
    func testMustRefreshRequestIsNeverSwallowed() {
        XCTAssertEqual(RefreshQueue.accept(refreshing: false, mustRefresh: false), .start)
        XCTAssertEqual(RefreshQueue.accept(refreshing: false, mustRefresh: true), .start)
        // 呢條就係「用家改咗 token、但嗰時正有輪跑緊」嘅入口：唔可以當冇事發生
        XCTAssertEqual(RefreshQueue.accept(refreshing: true, mustRefresh: true), .enqueue)
        // 呢條先係防止逐個字打網嘅併入
        XCTAssertEqual(RefreshQueue.accept(refreshing: true, mustRefresh: false), .merge)
    }

    /// 用決定砌一個假循環（唔碰網絡、唔碰 UI）：排隊嘅請求最終真係多跑一輪，
    /// 「順手」請求唔會增加打網次數，而循環會收斂（唔會一輪接一輪）。
    func testQueuedRequestsFinishInBoundedRounds() {
        // 跑緊嗰時收到：2 個一定要做到 + 3 個順手
        var pending = false
        for mustRefresh in [true, false, true, false, false] {
            switch RefreshQueue.accept(refreshing: true, mustRefresh: mustRefresh) {
            case .start: XCTFail("有輪跑緊唔應該同時再開一輪")
            case .enqueue: pending = true
            case .merge: break
            }
        }
        var rounds = 1
        var overshot = false
        while RefreshQueue.followUp(pending: pending, overshot: overshot) {
            rounds += 1
            pending = false      // 每輪開始清 latch（同 `ContentView.refreshQueued` 一樣）
            overshot = false
        }
        XCTAssertEqual(rounds, 2, "兩個 mustRefresh 請求併做一輪補跑就得，唔使一輪一個")
    }

    /// 順手請求（例如低耗電模式改變）喺跑緊時應該完全唔再加輪。
    func testMergedRequestAddsNoRounds() {
        let pending = false
        for _ in 0..<5 {
            if case .enqueue = RefreshQueue.accept(refreshing: true, mustRefresh: false) {
                XCTFail("mustRefresh: false 唔使排隊")
            }
        }
        XCTAssertFalse(RefreshQueue.followUp(pending: pending, overshot: false))
    }

    /// 設定輸入框：首次見到嘅值唔算「用家改過」（唔好一入分頁就打網）；改過先發；同一值唔重複發。
    func testTokenEditRules() {
        XCTAssertEqual(RefreshQueue.tokenEdit(current: "abc", lastFired: nil), .firstSeen)
        XCTAssertEqual(RefreshQueue.tokenEdit(current: "", lastFired: nil), .firstSeen)
        XCTAssertEqual(RefreshQueue.tokenEdit(current: "abc", lastFired: "abc"), .unchanged)
        XCTAssertEqual(RefreshQueue.tokenEdit(current: "abcd", lastFired: "abc"), .fire)
        // 刪返短都算改過（最後輸入一定要觸發）
        XCTAssertEqual(RefreshQueue.tokenEdit(current: "ab", lastFired: "abc"), .fire)
        XCTAssertEqual(RefreshQueue.settingsDebounceNanos, 500_000_000, "500 毫秒：即時得，又唔會逐個字打網")
    }

    /// 成段打字最終只觸發一次，而且觸發嘅係最新嗰個值（最後輸入一定做到、亦唔會逐字打網）。
    func testLastKeystrokeAlwaysFiresExactlyOnce() {
        var firedKey: String?
        var sent: [String] = []
        func step(_ current: String, cancelled: Bool) {
            let outcome = self.tokenTaskStep(current: current, firedKey: firedKey, cancelled: cancelled)
            firedKey = outcome.firedKey
            if outcome.fired { sent.append(current) }
        }
        // 入頁：已儲存嘅 token 唔算改過
        step("abc", cancelled: false)
        XCTAssertEqual(sent, [], "淨係入咗設定分頁唔應該打網")
        XCTAssertEqual(firedKey, "abc")
        // 打多一個字：debounce 未瞓完就畀下一個字取消 → 唔算觸發，`firedKey` 留舊值
        step("abcd", cancelled: true)
        XCTAssertEqual(sent, [])
        XCTAssertEqual(firedKey, "abc", "取消咗就唔好更新 firedKey，等最新嗰次先發")
        // 最後嗰個字冇人再改：一定發出，而且係最新值
        step("abcde", cancelled: false)
        XCTAssertEqual(sent, ["abcde"], "最後輸入一定要觸發一次，而且用最新嗰個值")
        // 同一個值再行多一次 task（例如返嚟呢個分頁）：唔使多打一次網
        step("abcde", cancelled: false)
        XCTAssertEqual(sent, ["abcde"])
    }

    // MARK: - 發現 2：輪進行中跨過嘅邊界

    /// 重排只收未來事件，所以 `crossed` 就係「呢個邊界會被剔除」嘅 latch；latch 到就一定要補跑，
    /// 唔然呢次跨過永久冇人補（鎖定畫面倒數會留低舊內容幾個鐘）。
    func testBoundaryCrossedDuringRoundTriggersCatchUpRound() {
        let armed = [at(2), at(600)]       // 一個好快就跨過、一個仲遠
        XCTAssertTrue(RefreshQueue.crossed(armed, now: at(3)), "本輪跑咗 3 秒：第一個已經喺期間跨過")
        XCTAssertTrue(RefreshQueue.followUp(pending: false, overshot: true))
        // 未跨過就唔補跑（唔會無端端多一輪）
        XCTAssertFalse(RefreshQueue.crossed(armed, now: now))
        XCTAssertFalse(RefreshQueue.followUp(pending: false, overshot: false))
    }

    /// 邊界本身已經係「事件時間 + 1 秒」，所以到正嗰一刻就應該算跨過（`>=`，唔係 `>`）。
    func testCrossedUsesInclusiveComparison() {
        let boundary = at(30)
        XCTAssertTrue(RefreshQueue.crossed([boundary], now: boundary))
        XCTAssertFalse(RefreshQueue.crossed([boundary], now: at(29)))
        XCTAssertTrue(RefreshQueue.crossed([boundary], now: at(31)))
    }

    // MARK: - 發現 3：非資料頁／inactive 期間跨過

    /// 其他分頁／唔喺前景期間跨過咗：清名單之前 latch `missed`，返嚟補跑一次。
    func testCrossingWhileNotWatchingIsCaughtUpOnReturn() {
        let armed = [at(30), at(120)]
        // 撳去「法院」分頁，或者落咗通知遮罩（唔喺 active）：跨過咗 → 記低
        XCTAssertEqual(RefreshQueue.tick(dataTab: false, active: true, boundaries: armed, missed: false, now: at(31)), .pause(missed: true))
        XCTAssertEqual(RefreshQueue.tick(dataTab: true, active: false, boundaries: armed, missed: false, now: at(31)), .pause(missed: true))
        // 返到「資料頁 + 前景」：補跑一次（名單由補跑嗰輪照最新資料重排）
        XCTAssertEqual(RefreshQueue.tick(dataTab: true, active: true, boundaries: [], missed: true, now: at(40)), .catchUp)
        // latch 清咗之後就唔會再補：返嚟正常監視
        XCTAssertEqual(
            RefreshQueue.tick(dataTab: true, active: true, boundaries: [at(100)], missed: false, now: at(40)),
            .rearm(crossed: false)
        )
    }

    /// 離開期間嘅 latch 要黏住：名單清咗之後再 tick 都唔可以當冇發生過。
    func testMissedLatchIsStickyWhileAway() {
        XCTAssertEqual(RefreshQueue.tick(dataTab: false, active: true, boundaries: [at(30)], missed: false, now: at(40)), .pause(missed: true))
        XCTAssertEqual(RefreshQueue.tick(dataTab: false, active: true, boundaries: [], missed: true, now: at(200)), .pause(missed: true))
        XCTAssertEqual(RefreshQueue.tick(dataTab: true, active: false, boundaries: [], missed: true, now: at(240)), .pause(missed: true))
    }

    /// 離開時根本冇跨過：唔使記、返嚟亦唔補跑（唔會因為切返分頁就多打一次網）。
    func testNothingCrossedWhileAwayMeansNoCatchUp() {
        XCTAssertEqual(RefreshQueue.tick(dataTab: false, active: true, boundaries: [at(300)], missed: false, now: at(40)), .pause(missed: false))
        XCTAssertEqual(RefreshQueue.tick(dataTab: false, active: true, boundaries: [], missed: false, now: at(900)), .pause(missed: false))
        XCTAssertEqual(RefreshQueue.tick(dataTab: true, active: true, boundaries: [], missed: false, now: at(900)), .rearm(crossed: false))
    }

    // MARK: - 發現 4：冇跨過就唔打網

    /// 名單空（未排過、或者全部已過）唔算跨過 → 唔會憑空打網。
    func testEmptyListCrossesNothing() {
        XCTAssertFalse(RefreshQueue.crossed([], now: now))
        XCTAssertFalse(RefreshQueue.crossed([], now: at(10 * 3_600)))
        XCTAssertFalse(RefreshQueue.followUp(pending: false, overshot: false))
    }

    /// 前景監視緊、未跨過 → 只重排名單；跨過咗先要 refresh。
    func testWatchingRefreshesOnlyWhenCrossed() {
        XCTAssertEqual(
            RefreshQueue.tick(dataTab: true, active: true, boundaries: [at(100)], missed: false, now: at(40)),
            .rearm(crossed: false)
        )
        XCTAssertEqual(
            RefreshQueue.tick(dataTab: true, active: true, boundaries: [at(30)], missed: false, now: at(31)),
            .rearm(crossed: true)
        )
    }
}
