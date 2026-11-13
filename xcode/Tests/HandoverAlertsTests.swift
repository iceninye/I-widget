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
            "15 分鐘後喺八鄉廠 W1F準備 Run 13，之後開去屯門",
            "15 分鐘後喺屯門落地，Run 13，之後 09:19 喺屯門接 Run 16",
            "15 分鐘後你要喺屯門接 Run 16，開去錦上路 2",
            "15 分鐘後喺錦上路 2落地，接你嗰位係 118 更，之後用膳到 11:16",
            "15 分鐘後你要喺錦上路 2接 128 更嘅 Run 18，開去烏溪沙",
            "最後一程，15 分鐘後喺烏溪沙落地，Run 18，之後收工",
        ])
        let afterMeal = alerts[4]
        XCTAssertEqual(afterMeal.kind, .pickUp)
        XCTAssertEqual(afterMeal.title, "接車 11:16 · Run 18")
        // 2026-11-13 11:16:18 香港時間 = 03:16:18 UTC，提前 15 分鐘
        XCTAssertEqual(afterMeal.eventAt, ISO8601DateFormatter().date(from: "2026-11-13T03:16:18Z"))
        XCTAssertEqual(afterMeal.fireAt, ISO8601DateFormatter().date(from: "2026-11-13T03:01:18Z"))
        XCTAssertEqual(Set(alerts.map(\.id)).count, alerts.count)
        XCTAssertTrue(alerts.allSatisfy { $0.id.hasPrefix(HandoverAlerts.idPrefix) })
        // detail = body 去走「N 分鐘後」（Live Activity 倒數用）
        XCTAssertEqual(alerts[3].detail, "喺錦上路 2落地，接你嗰位係 118 更，之後用膳到 11:16")
        XCTAssertEqual(alerts[4].detail, "你要喺錦上路 2接 128 更嘅 Run 18，開去烏溪沙")
        XCTAssertEqual(alerts[5].detail, "喺烏溪沙落地，Run 18，之後收工")
        XCTAssertTrue(alerts.allSatisfy { !$0.detail.isEmpty && $0.body.hasSuffix($0.detail) && !$0.detail.contains("分鐘後") })
    }

    func testLeadsFollowSettings() throws {
        var settings = HandoverSettings()
        settings.pickUp = 5
        settings.dropOff = 0
        settings.mealEnd = 30
        settings.lastDrop = 10
        let alerts = HandoverAlerts.make(card: try card(), date: "2026-11-13", places: places, settings: settings)
        XCTAssertEqual(alerts.map(\.body), [
            "5 分鐘後喺八鄉廠 W1F準備 Run 13，之後開去屯門",
            "5 分鐘後你要喺屯門接 Run 16，開去錦上路 2",
            "30 分鐘後你要喺錦上路 2接 128 更嘅 Run 18，開去烏溪沙",
            "最後一程，10 分鐘後喺烏溪沙落地，Run 18，之後收工",
        ])
        XCTAssertEqual(alerts[2].fireAt, ISO8601DateFormatter().date(from: "2026-11-13T02:46:18Z"))
    }

    func testParkAndRideAreAnnounced() throws {
        let json = #"""
        {"duties":[{"id":"8027501","on":[20000,"HUH"],"off":[40000,"HUH"],
          "legs":[["drive",5,"HUH3",21000,"TUM",24000],["ride",5,"TUM",24300,"HUH2",27000],
                  ["park",7,"HUH3",28000,"ETS1",28300],["drive",9,"ETS2",30000,"HUH2",30600],
                  ["park",9,"HUH2",30600,"LT1",31000]]}]}
        """#
        let card = try XCTUnwrap(DutyData.parseCards(Data(json.utf8), ids: ["8027501"])["8027501"])
        let names = PlaceNames(stations: ["HUH": "紅磡", "TUM": "屯門", "ETS": "尖東"], places: [:])
        let bodies = HandoverAlerts.make(card: card, date: "2026-11-13", places: names).map(\.body)
        XCTAssertEqual(bodies, [
            "15 分鐘後你要喺紅磡 3接 Run 5，開去屯門",
            "15 分鐘後喺屯門落地，Run 5，之後搭車去紅磡 2",
            "15 分鐘後你要喺紅磡 3接 Run 7，泊車去尖東 1",
            "15 分鐘後喺尖東 1泊好車，Run 7，之後 08:20 喺尖東 2接 Run 9",
            "15 分鐘後你要喺尖東 2接 Run 9，開去紅磡廠 LT1，之後泊車",
            "最後一程，15 分鐘後喺紅磡廠 LT1泊好車，Run 9，之後收工",
        ])
    }

    func testDutyAlerts() {
        var day = DutyDay(date: "2026-11-13", code: "8027111", kind: .duty, title: "早更 8027111")
        day.on = 19200
        day.off = 49800
        day.onPlace = "八鄉廠"
        day.offPlace = "錦上路"
        var settings = HandoverSettings()
        XCTAssertTrue(HandoverAlerts.dutyAlerts(day: day, settings: settings).allSatisfy { $0.body.hasSuffix($0.detail) && !$0.detail.isEmpty })
        XCTAssertEqual(HandoverAlerts.dutyAlerts(day: day, settings: settings).map(\.body), [
            "1 小時後返工，05:20 喺八鄉廠，111 更",
            "15 分鐘後返工，05:20 喺八鄉廠，111 更",
        ])
        settings.onFirst = 90
        settings.onSecond = 90
        settings.off = 15
        let alerts = HandoverAlerts.dutyAlerts(day: day, settings: settings)
        XCTAssertEqual(alerts.map(\.body), ["1 小時 30 分鐘後返工，05:20 喺八鄉廠，111 更", "15 分鐘後收工，13:50 喺錦上路"])
        // 05:20 香港時間 = 前一日 21:20 UTC，提前 90 分鐘
        XCTAssertEqual(alerts[0].fireAt, ISO8601DateFormatter().date(from: "2026-11-12T19:50:00Z"))

        var rest = DutyDay(date: "2026-11-14", code: "RD", kind: .rest, title: "休息")
        rest.on = nil
        XCTAssertEqual(HandoverAlerts.dutyAlerts(day: rest), [])
    }

    func testSettingsDecodeFillsDefaults() throws {
        let old = try JSONDecoder().decode(HandoverSettings.self, from: Data(#"{"pickUp":5,"rate":9}"#.utf8))
        XCTAssertEqual(old.pickUp, 5)
        XCTAssertEqual(old.onFirst, 60)
        XCTAssertEqual(old.dropOff, 15)
        XCTAssertEqual(old.rate, 0.65)
        XCTAssertTrue(old.speak)
        let saved = try JSONEncoder().encode(old)
        XCTAssertEqual(try JSONDecoder().decode(HandoverSettings.self, from: saved), old)
    }

    func testShortId() {
        XCTAssertEqual(HandoverAlerts.short("8027118"), "118")
        XCTAssertEqual(HandoverAlerts.short("SLP"), "SLP")
    }
}
