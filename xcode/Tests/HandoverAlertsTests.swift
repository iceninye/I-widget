import XCTest

final class HandoverAlertsTests: XCTestCase {
    /// 虛構 Duty Sheet：111 落車交俾 118，用膳後接 128 嘅 Run 18。
    private let json = #"""
    {"duties":[
      {"id":"8027111","group":"KSR","on":[19200,"PHD"],"off":[49800,"KSR"],"work":480,
       "meal":[34454,40578,"KSR2","KSR2"],
       "legs":[["prep",13,"W1F",22059,"KSR1",22185],["drive",13,"KSR1",22185,"TUM",23160],
               ["drive",16,"TUM",33540,"KSR2",34454],["drive",18,"KSR2",40578,"WKS",44080]]},
      {"id":"8027118","on":[30000,"KSR"],"off":[60000,"KSR"],
       "legs":[["drive",16,"KSR2",34600,"TUM",35500]]},
      {"id":"8027128","on":[30000,"TUM"],"off":[60000,"KSR"],
       "legs":[["drive",18,"TUM",39000,"KSR2",40500],["ride",99,"KSR2",40600,"TUM",41000]]}
    ]}
    """#

    private let places = PlaceNames(stations: ["KSR": "錦上路", "TUM": "屯門", "WKS": "烏溪沙"], places: [:])

    private func card() throws -> DutyCard {
        try XCTUnwrap(DutyData.parseCards(Data(json.utf8), ids: ["8027111"])["8027111"])
    }

    func testStationGroupsPlatforms() {
        XCTAssertEqual(Relief.station("KSR1"), "KSR")
        XCTAssertEqual(Relief.station("KSR2"), "KSR")
        XCTAssertEqual(Relief.station("TUM"), "TUM")
        XCTAssertEqual(Relief.station("W1F"), "W1F")
    }

    func testParseKeepsLegsAndReliefs() throws {
        let card = try card()
        XCTAssertEqual(card.legs?.count, 4)
        XCTAssertEqual(card.legs?[3], DutyLeg(kind: "drive", run: 18, from: "KSR2", at: 40578, to: "WKS", until: 44080))
        XCTAssertEqual(card.reliefs?.count, 4)
        XCTAssertEqual(card.reliefs?[2].to, DutyRelief(id: "8027118", at: 34600, place: "KSR2"))
        XCTAssertNil(card.reliefs?[2].from)
        XCTAssertEqual(card.reliefs?[3].from, DutyRelief(id: "8027128", at: 40500, place: "KSR2"))
        // 出車準備之後直接開同一個 Run：唔算交接
        XCTAssertEqual(card.reliefs?[0], LegRelief.none)
    }

    func testAlertsForEveryHandover() throws {
        let alerts = HandoverAlerts.make(card: try card(), date: "2026-11-13", places: places)
        XCTAssertEqual(alerts.map(\.body), [
            "5 分鐘後喺八鄉廠 W1F準備 Run 13",
            "5 分鐘後喺屯門落地（Run 13）",
            "5 分鐘後你要喺屯門接 Run 16",
            "5 分鐘後喺錦上路 2落地，接你嗰位係 118 更",
            "15 分鐘後你要喺錦上路 2接 128 更嘅 Run 18",
            "5 分鐘後喺烏溪沙落地（Run 18）",
        ])
        let afterMeal = alerts[4]
        XCTAssertEqual(afterMeal.kind, .pickUp)
        XCTAssertEqual(afterMeal.title, "接車 11:16 · Run 18")
        // 2026-11-13 11:16:18 香港時間 = 03:16:18 UTC，提前 15 分鐘
        XCTAssertEqual(afterMeal.eventAt, ISO8601DateFormatter().date(from: "2026-11-13T03:16:18Z"))
        XCTAssertEqual(afterMeal.fireAt, ISO8601DateFormatter().date(from: "2026-11-13T03:01:18Z"))
        XCTAssertEqual(Set(alerts.map(\.id)).count, alerts.count)
        XCTAssertTrue(alerts.allSatisfy { $0.id.hasPrefix(HandoverAlerts.idPrefix) })
    }

    func testNoLegsNoAlerts() {
        let card = DutyCard(id: "1101101", group: nil, on: 20000, onPlace: "KSR", off: 50000, offPlace: "KSR", work: nil, meal: nil)
        XCTAssertEqual(HandoverAlerts.make(card: card, date: "2026-11-13", places: places), [])
    }

    func testShortId() {
        XCTAssertEqual(HandoverAlerts.short("8027118"), "118")
        XCTAssertEqual(HandoverAlerts.short("SLP"), "SLP")
    }
}
