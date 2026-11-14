import XCTest

final class DutyCountdownTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func event(
        _ kind: HandoverAlert.Kind, _ minutes: Double, _ title: String, place: String = "", note: String = ""
    ) -> DutyEvent {
        DutyEvent(
            kind: kind, at: now.addingTimeInterval(minutes * 60), title: title, detail: "\(title) 詳情", place: place, note: note
        )
    }

    private func alert(
        _ kind: HandoverAlert.Kind, id: String, fire: Double, event: Double, title: String,
        detail: String = "", place: String = "", note: String = ""
    ) -> HandoverAlert {
        HandoverAlert(
            id: id, kind: kind, fireAt: now.addingTimeInterval(fire * 60), eventAt: now.addingTimeInterval(event * 60),
            title: title, body: "15 分鐘後\(detail)", detail: detail, place: place, note: note
        )
    }

    func testStatePicksNextAndTwoLaterWithTimes() {
        let events = [
            event(.dropOff, 120, "落地 B", place: "錦上路 2", note: "Run 16 · 交 118 更"),
            event(.on, 30, "返工", place: "八鄉廠", note: "111 更"),
            event(.pickUp, 60, "接車 A", place: "屯門", note: "Run 18 → 烏溪沙"),
            event(.off, 300, "放工"),
            event(.dropOff, -10, "已過"),
        ]
        guard let state = DutyActivityPlan.state(events: events, now: now) else { return XCTFail("應該有下一件事") }
        XCTAssertEqual(state.kind, "on")
        // 主行只靠 action，渲染唔使再拆 title
        XCTAssertEqual(state.action, "返工")
        XCTAssertEqual(state.at, now.addingTimeInterval(30 * 60))
        XCTAssertEqual(state.place, "八鄉廠")
        XCTAssertEqual(state.note, "111 更")
        XCTAssertEqual(state.syncedAt, now)
        // later 係結構化項目，帶時間、地點、補充（渲染時先可以判過期）
        XCTAssertEqual(state.later.count, 2)
        XCTAssertEqual(state.later.map(\.action), ["接車", "落地"])
        XCTAssertEqual(state.later.map(\.at), [now.addingTimeInterval(60 * 60), now.addingTimeInterval(120 * 60)])
        XCTAssertEqual(state.later.map(\.place), ["屯門", "錦上路 2"])
        XCTAssertEqual(state.later.map(\.note), ["Run 18 → 烏溪沙", "Run 16 · 交 118 更"])
        XCTAssertEqual(state.later.map(\.kind), ["pick", "drop"])
        XCTAssertFalse(state.later.isEmpty)
        // 每個 later 都有 id（ForEach 用），同一 kind + 同一時間就係同一行
        XCTAssertEqual(state.later[0].id, DutyLaterItem(kind: "pick", at: state.later[0].at).id)
    }

    func testStateNilWhenNothingUpcoming() {
        XCTAssertNil(DutyActivityPlan.state(events: [], now: now))
        XCTAssertNil(DutyActivityPlan.state(events: [event(.dropOff, -1, "已過")], now: now))
    }

    func testWaitsUntilLeadWindow() {
        let events = [event(.on, 240, "返工")]
        XCTAssertEqual(DutyActivityPlan.decide(events: events, now: now, running: false, startedAt: nil, leadMinutes: 180), .wait)
        guard case .start(let state) = DutyActivityPlan.decide(events: events, now: now.addingTimeInterval(61 * 60), running: false, startedAt: nil, leadMinutes: 180) else {
            return XCTFail("應該開始")
        }
        XCTAssertEqual(state.action, "返工")
        // 剛好喺邊界：3 小時前就開始
        guard case .start = DutyActivityPlan.decide(events: events, now: now.addingTimeInterval(60 * 60), running: false, startedAt: nil, leadMinutes: 180) else {
            return XCTFail("邊界應該開始")
        }
    }

    /// 新語意：行緊活動但下一件事超出 lead 窗口 → 結束，唔好長駐十幾個鐘後嘅倒數。
    func testRunningOutsideHorizonEndsInsteadOfStalling() {
        let events = [event(.pickUp, 400, "接車")]
        XCTAssertEqual(
            DutyActivityPlan.decide(events: events, now: now, running: true, startedAt: now.addingTimeInterval(-3_600), leadMinutes: 60), .end
        )
        // 冇活動行緊、又未入窗口：等，唔使結束
        XCTAssertEqual(
            DutyActivityPlan.decide(events: events, now: now, running: false, startedAt: nil, leadMinutes: 60), .wait
        )
        // 入咗窗口（剩返 60 分鐘）先繼續倒數
        guard case .update(let state) = DutyActivityPlan.decide(
            events: events, now: now.addingTimeInterval(340 * 60), running: true, startedAt: now, leadMinutes: 60
        ) else {
            return XCTFail("入窗口應該更新")
        }
        XCTAssertEqual(state.action, "接車")
    }

    func testRestartsAfterSixHours() {
        let events = [event(.dropOff, 30, "落地")]
        let old = now.addingTimeInterval(-(6 * 3_600 + 60))
        guard case .start = DutyActivityPlan.decide(events: events, now: now, running: true, startedAt: old, leadMinutes: 180) else {
            return XCTFail("超過 6 小時要開新嘅")
        }
        guard case .update = DutyActivityPlan.decide(events: events, now: now, running: true, startedAt: now.addingTimeInterval(-5 * 3_600), leadMinutes: 180) else {
            return XCTFail("5 小時未使重開")
        }
        // 6 小時係本 app 主動輪替門檻，系統上限係 8 小時
        XCTAssertEqual(DutyActivityPlan.maxAge, 6 * 3_600)
        XCTAssertLessThan(DutyActivityPlan.maxAge, 8 * 3_600)
    }

    func testEndsWhenNothingLeft() {
        XCTAssertEqual(DutyActivityPlan.decide(events: [], now: now, running: true, startedAt: nil, leadMinutes: 180), .end)
        XCTAssertEqual(DutyActivityPlan.decide(events: [], now: now, running: false, startedAt: nil, leadMinutes: 180), .wait)
    }

    func testEventsMergeDuplicatesAndDropPast() {
        let alerts = [
            alert(.on, id: "a", fire: -30, event: 30, title: "返工 08:00", detail: "返工，08:00", place: "八鄉廠", note: "111 更"),
            alert(.on, id: "b", fire: 15, event: 30, title: "返工 08:00", detail: "返工，08:00", place: "八鄉廠", note: "111 更"),
            alert(.dropOff, id: "c", fire: 100, event: 120, title: "落地 10:00", detail: "喺錦上路落地", place: "錦上路 2", note: "Run 16 · 交 118 更"),
            alert(.pickUp, id: "d", fire: -50, event: -5, title: "接車 已過"),
        ]
        let events = DutyEvent.upcoming(from: alerts, now: now)
        XCTAssertEqual(events.map(\.title), ["返工 08:00", "落地 10:00"])
        XCTAssertEqual(events.first?.detail, "返工，08:00")
        // 交接資料要帶到 Live Activity：地點 + 補充
        XCTAssertEqual(events.first?.place, "八鄉廠")
        XCTAssertEqual(events.first?.note, "111 更")
        XCTAssertEqual(events.last?.place, "錦上路 2")
    }

    func testPastEventsAreNotListedAsUpcoming() {
        let events = [event(.on, 30, "返工"), event(.pickUp, 60, "接車"), event(.dropOff, 120, "落地")]
        guard let state = DutyActivityPlan.state(events: events, now: now) else { return XCTFail("應該有下一件事") }
        XCTAssertFalse(state.isPast(now: now))
        XCTAssertTrue(state.isPast(now: now.addingTimeInterval(31 * 60)))
        XCTAssertEqual(state.later.count, DutyActivityPlan.maxLaterItems)
        // 過咗 90 分鐘：接車已過期，唔可以再列為即將發生
        XCTAssertEqual(state.upcomingLater(now: now.addingTimeInterval(90 * 60)).map(\.action), ["落地"])
        XCTAssertEqual(state.upcomingLater(now: now.addingTimeInterval(3 * 3_600)).count, 0)
    }

    /// stale（系統過咗 `staleDate`）：講「待更新」+「上次事件」，唔好講「已到」，亦唔好列之後嘅事。
    func testStaleWordingIsPendingNotCompleted() throws {
        let events = [event(.on, 30, "返工", place: "八鄉廠", note: "111 更"), event(.pickUp, 60, "接車")]
        let state = try XCTUnwrap(DutyActivityPlan.state(events: events, now: now))
        let late = now.addingTimeInterval(31 * 60)
        let staleText = state.accessibilityText(now: late, stale: true)
        XCTAssertTrue(staleText.contains("待更新"), staleText)
        XCTAssertTrue(staleText.contains("上次事件"), staleText)
        XCTAssertTrue(staleText.contains("返工"), staleText)
        XCTAssertFalse(staleText.contains("已到"), staleText)
        XCTAssertFalse(staleText.contains("之後"), staleText)
        let freshText = state.accessibilityText(now: now, stale: false)
        XCTAssertTrue(freshText.contains("下一件事"), freshText)
        XCTAssertTrue(freshText.contains("八鄉廠"), freshText)
        XCTAssertTrue(freshText.contains("之後"), freshText)
    }

    func testEventsSortAcrossMidnight() throws {
        // 服務日 2026-11-13：23:45（85_500 秒）之後仲有過咗午夜嘅 00:20（86_400 + 1_200 秒）
        let before = try XCTUnwrap(HandoverAlerts.moment(date: "2026-11-13", second: 85_500))
        let afterMidnight = try XCTUnwrap(HandoverAlerts.moment(date: "2026-11-13", second: 86_400 + 1_200))
        XCTAssertTrue(afterMidnight > before, "過咗午夜要排喺 23:45 之後")
        let early = before.addingTimeInterval(-2 * 3_600)
        let alerts = [
            HandoverAlert(
                id: "x2", kind: .off, fireAt: early, eventAt: afterMidnight, title: "放工 00:20", body: "15 分鐘後收工",
                detail: "收工", place: "紅磡廠", note: "111 更"
            ),
            HandoverAlert(
                id: "x1", kind: .pickUp, fireAt: early, eventAt: before, title: "接車 23:45", body: "15 分鐘後接車",
                detail: "接車", place: "屯門", note: "Run 7"
            ),
        ]
        let events = DutyEvent.upcoming(from: alerts, now: early)
        XCTAssertEqual(events.map(\.title), ["接車 23:45", "放工 00:20"])
        guard let state = DutyActivityPlan.state(events: events, now: early) else { return XCTFail("應該有下一件事") }
        XCTAssertEqual(state.action, "接車")
        XCTAssertEqual(state.at, before)
        XCTAssertEqual(state.later.map(\.action), ["放工"])
        XCTAssertEqual(state.later.map(\.at), [afterMidnight])
    }

    func testLimitedKeepsContentUnder4KB() {
        // 極端輸入：幾千個中文字（一個中文字 JSON 編碼後最多 6 字節）+ 8 個 later
        let fat = String(repeating: "錦上路交記月台候補", count: 400)
        XCTAssertGreaterThan(fat.count, 3_000)
        let many = (0..<8).map { DutyLaterItem(kind: "drop", at: now.addingTimeInterval(Double($0) * 60), place: fat, note: fat) }
        let state = DutyActivityState(kind: "drop", at: now, place: fat, note: fat, later: many, syncedAt: now)
        XCTAssertGreaterThan(DutyActivityPlan.byteCount(state), DutyActivityPlan.contentByteLimit)

        let small = DutyActivityPlan.limited(state)
        XCTAssertEqual(small.later.count, DutyActivityPlan.maxLaterItems)
        XCTAssertLessThanOrEqual(small.place.count, DutyActivityPlan.maxPlaceCharacters)
        XCTAssertLessThanOrEqual(small.note.count, DutyActivityPlan.maxNoteCharacters)
        XCTAssertLessThanOrEqual(DutyActivityPlan.byteCount(small), DutyActivityPlan.contentByteLimit)
        // 時間同 kind 唔可以喺收窄時失去
        XCTAssertEqual(small.kind, "drop")
        XCTAssertEqual(small.at, state.at)
        XCTAssertEqual(small.syncedAt, state.syncedAt)
        XCTAssertEqual(small.later.map(\.at), many.prefix(2).map(\.at))

        // 由事件砌出嘅 state 都應該已經收細（`state(events:now:)` 內部會 clamp）
        let events = [event(.pickUp, 30, "接車", place: fat, note: fat), event(.dropOff, 60, "落地", place: fat, note: fat)]
        guard let built = DutyActivityPlan.state(events: events, now: now) else { return XCTFail("應該有下一件事") }
        XCTAssertLessThanOrEqual(DutyActivityPlan.byteCount(built), DutyActivityPlan.contentByteLimit)
    }

    /// 舊版（title/detail/later:[String]）嘅 Live Activity 內容：更新 app 之後都要讀到，唔可以 throw。
    func testDecodesLegacyStateShape() throws {
        let legacy = #"{"kind":"on","title":"返工 05:20 · 八鄉廠","detail":"返工，05:20","at":1800000000,"later":["接車 06:00"]}"#
        let state = try JSONDecoder().decode(DutyActivityState.self, from: Data(legacy.utf8))
        XCTAssertEqual(state.kind, "on")
        XCTAssertEqual(state.action, "返工")
        XCTAssertEqual(state.at, now)
        XCTAssertEqual(state.syncedAt, now)
        XCTAssertEqual(state.place, "")
        XCTAssertEqual(state.note, "")
        XCTAssertTrue(state.later.isEmpty)
        // 新版編码之後照樣讀返（round-trip）
        let fresh = try XCTUnwrap(DutyActivityPlan.state(events: [event(.on, 30, "返工", place: "八鄉廠", note: "111 更")], now: now))
        let data = try JSONEncoder().encode(fresh)
        XCTAssertEqual(try JSONDecoder().decode(DutyActivityState.self, from: data), fresh)
    }
}
