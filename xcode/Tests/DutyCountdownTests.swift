import XCTest

final class DutyCountdownTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func event(_ kind: HandoverAlert.Kind, _ minutes: Double, _ title: String) -> DutyEvent {
        DutyEvent(kind: kind, at: now.addingTimeInterval(minutes * 60), title: title, detail: "\(title) 詳情")
    }

    private func alert(_ kind: HandoverAlert.Kind, id: String, fire: Double, event: Double, title: String, detail: String = "") -> HandoverAlert {
        HandoverAlert(
            id: id, kind: kind, fireAt: now.addingTimeInterval(fire * 60), eventAt: now.addingTimeInterval(event * 60),
            title: title, body: "15 分鐘後\(detail)", detail: detail
        )
    }

    func testStatePicksNextAndTwoLater() {
        let events = [event(.drop, 120, "落地 B"), event(.on, 30, "返工"), event(.pick, 60, "接車 A"), event(.off, 300, "放工"), event(.drop, -10, "已過")]
        let state = DutyActivityPlan.state(events: events, now: now)
        XCTAssertEqual(state?.kind, "on")
        XCTAssertEqual(state?.title, "返工")
        XCTAssertEqual(state?.at, now.addingTimeInterval(30 * 60))
        XCTAssertEqual(state?.later, ["接車 A", "落地 B"])
    }

    func testStateNilWhenNothingUpcoming() {
        XCTAssertNil(DutyActivityPlan.state(events: [], now: now))
        XCTAssertNil(DutyActivityPlan.state(events: [event(.drop, -1, "已過")], now: now))
    }

    func testWaitsUntilLeadWindow() {
        let events = [event(.on, 240, "返工")]
        XCTAssertEqual(DutyActivityPlan.decide(events: events, now: now, running: false, startedAt: nil, leadMinutes: 180), .wait)
        guard case .start(let state) = DutyActivityPlan.decide(events: events, now: now.addingTimeInterval(61 * 60), running: false, startedAt: nil, leadMinutes: 180) else {
            return XCTFail("應該開始")
        }
        XCTAssertEqual(state.title, "返工")
        // 剛好喺邊界：3 小時前就開始
        guard case .start = DutyActivityPlan.decide(events: events, now: now.addingTimeInterval(60 * 60), running: false, startedAt: nil, leadMinutes: 180) else {
            return XCTFail("邊界應該開始")
        }
    }

    func testRunningUpdatesEvenOutsideLead() {
        let events = [event(.pick, 400, "接車")]
        guard case .update(let state) = DutyActivityPlan.decide(events: events, now: now, running: true, startedAt: now.addingTimeInterval(-3_600), leadMinutes: 60) else {
            return XCTFail("行緊就更新")
        }
        XCTAssertEqual(state.title, "接車")
    }

    func testRestartsAfterSixHours() {
        let events = [event(.drop, 30, "落地")]
        let old = now.addingTimeInterval(-(6 * 3_600 + 60))
        guard case .start = DutyActivityPlan.decide(events: events, now: now, running: true, startedAt: old, leadMinutes: 180) else {
            return XCTFail("超過 6 小時要開新嘅")
        }
        guard case .update = DutyActivityPlan.decide(events: events, now: now, running: true, startedAt: now.addingTimeInterval(-5 * 3_600), leadMinutes: 180) else {
            return XCTFail("5 小時未使重開")
        }
    }

    func testEndsWhenNothingLeft() {
        XCTAssertEqual(DutyActivityPlan.decide(events: [], now: now, running: true, startedAt: nil, leadMinutes: 180), .end)
        XCTAssertEqual(DutyActivityPlan.decide(events: [], now: now, running: false, startedAt: nil, leadMinutes: 180), .wait)
    }

    func testEventsMergeDuplicatesAndDropPast() {
        let alerts = [
            alert(.on, id: "a", fire: -30, event: 30, title: "返工 08:00", detail: "返工，08:00"),
            alert(.on, id: "b", fire: 15, event: 30, title: "返工 08:00", detail: "返工，08:00"),
            alert(.drop, id: "c", fire: 100, event: 120, title: "落地 10:00", detail: "喺錦上路落地"),
            alert(.pick, id: "d", fire: -50, event: -5, title: "接車 已過"),
        ]
        let events = DutyEvent.upcoming(from: alerts, now: now)
        XCTAssertEqual(events.map(\.title), ["返工 08:00", "落地 10:00"])
        XCTAssertEqual(events.first?.detail, "返工，08:00")
    }
}
