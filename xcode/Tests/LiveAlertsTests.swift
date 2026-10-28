import XCTest

final class LiveAlertsTests: XCTestCase {
    func testWarningsParseAndSkipCancelled() throws {
        let json = #"{"WRAIN":{"name":"暴雨警告信號","code":"WRAINR","actionCode":"ISSUE"},"WTCSGNL":{"name":"熱帶氣旋警告信號","code":"TC3","actionCode":"REISSUE"},"WHOT":{"name":"酷熱天氣警告","code":"WHOT","actionCode":"CANCEL"},"WTS":{"name":"雷暴警告","actionCode":"ISSUE"}}"#
        let warnings = try HKOWarnings.parse(Data(json.utf8))
        XCTAssertEqual(warnings, [
            WeatherWarning(text: "紅色暴雨", severe: true),
            WeatherWarning(text: "三號風球", severe: false),
            WeatherWarning(text: "雷暴警告", severe: false),
        ])
        XCTAssertEqual(try HKOWarnings.parse(Data("{}".utf8)), [])
        XCTAssertThrowsError(try HKOWarnings.parse(Data("[]".utf8)))
    }

    func testTrainStatus() throws {
        let normal = #"{"status":1,"message":"successful","isdelay":"N","data":{}}"#
        let delayed = #"{"status":1,"message":"successful","isdelay":"Y","data":{}}"#
        let special = #"{"status":0,"message":"特別車務安排","url":"https://www.mtr.com.hk"}"#
        XCTAssertEqual(try MTRStatus.parse(Data(normal.utf8)).state, .normal)
        XCTAssertEqual(try MTRStatus.parse(Data(delayed.utf8)).state, .delayed)
        let notice = try MTRStatus.parse(Data(special.utf8))
        XCTAssertEqual(notice.state, .special)
        XCTAssertEqual(notice.message, "特別車務安排")
        XCTAssertThrowsError(try MTRStatus.parse(Data(#"{"status":2}"#.utf8)))
    }

    private func aqhiItem(station: String = "中西區", type: String = "一般監測站", index: String = "4", risk: String = "中", time: String = "Wed, 28 Oct 2026 22:30:00 +0800") -> String {
        "<item><title>\(station)</title><pubDate>\(time)</pubDate><description><![CDATA[\(station) - \(type): \(index) \(risk) - 2026年10月28日 (星期三)]]></description></item>"
    }

    private func rss(_ items: String) -> Data {
        Data("<?xml version=\"1.0\" encoding=\"UTF-8\"?><rss version=\"2.0\"><channel>\(items)</channel></rss>".utf8)
    }

    func testAQHIUsesNamedGeneralStationNotMaximum() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let data = rss(aqhiItem(station: "屯門", index: "10+", risk: "嚴重")
                       + aqhiItem() + aqhiItem(station: "中環", type: "路邊監測站", index: "10", risk: "甚高"))
        let air = try EPDAQHI.parse(data, now: now)
        XCTAssertEqual(air.index, "4")
        XCTAssertEqual(air.level, "中")
        XCTAssertEqual(air.station, "中西區（一般監測站）")
        XCTAssertFalse(air.isPoor)
        XCTAssertEqual(air.observedAt, HKODate.iso("2026-10-28T22:30:00+08:00"))
        XCTAssertEqual(air.fetchedAt, now)
        XCTAssertNotEqual(air.observedAt, air.fetchedAt)
        XCTAssertNotEqual(EPDAQHI.cacheKey, "air")
    }

    func testAQHIRiskBoundariesAndTenPlus() throws {
        for (index, risk, poor) in [("1", "低", false), ("3", "低", false), ("4", "中", false),
                                     ("6", "中", false), ("7", "高", true), ("8", "甚高", true),
                                     ("10", "甚高", true), ("10+", "嚴重", true)] {
            let air = try EPDAQHI.parse(rss(aqhiItem(index: index, risk: risk)))
            XCTAssertEqual(air.index, index)
            XCTAssertEqual(air.level, risk)
            XCTAssertEqual(air.isPoor, poor)
        }
        XCTAssertNil(EPDAQHI.riskLevel("0"))
        XCTAssertNil(EPDAQHI.riskLevel("11"))
    }

    func testAQHIRejectsMissingMalformedAndRoadsideData() throws {
        for item in ["", aqhiItem(station: "屯門"), aqhiItem(type: "路邊監測站"),
                     aqhiItem(index: "-"), aqhiItem(index: "0"), aqhiItem(index: "11"),
                     aqhiItem(index: "4.5"), aqhiItem(index: "10+garbage", risk: "嚴重"),
                     aqhiItem(index: "4", risk: "低")] {
            XCTAssertThrowsError(try EPDAQHI.parse(rss(item)))
        }
        for value in ["", "<rss><channel>", "<html>upstream unavailable</html>",
                      "{\"current\":{\"us_aqi\":42}}", "<!DOCTYPE rss [<!ENTITY x '4'>]><rss/>"] {
            XCTAssertThrowsError(try EPDAQHI.parse(Data(value.utf8)))
        }
        XCTAssertNil(try EPDAQHI.parse(rss(aqhiItem(time: "invalid"))).observedAt)
    }

    func testAQHIRSSSupportsEscapedDescriptionAndBOM() throws {
        let item = aqhiItem(index: "10+", risk: "嚴重")
            .replacingOccurrences(of: "<![CDATA[", with: "")
            .replacingOccurrences(of: "]]>", with: "")
            .replacingOccurrences(of: "10+", with: "10&#43;")
        let data = Data([0xEF, 0xBB, 0xBF]) + rss(item)
        XCTAssertEqual(try EPDAQHI.parse(data).index, "10+")
    }

    func testAQHIFreshnessUsesPublicationRatherThanDownloadTime() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        var air = AirQuality(index: "4", level: "中", station: "中西區", observedAt: now, fetchedAt: now)
        XCTAssertFalse(air.isStale(at: now.addingTimeInterval(5399)))
        XCTAssertTrue(air.isStale(at: now.addingTimeInterval(5400)))
        XCTAssertTrue(air.isStale(at: now.addingTimeInterval(-1)))
        air.observedAt = now.addingTimeInterval(-7200)
        XCTAssertTrue(air.isStale(at: now))
        air.observedAt = nil
        XCTAssertTrue(air.isStale(at: now))
    }

    func testLiveConditionsExpireWithinPrecomputedTimeline() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        var info = ExtraInfo.sample
        info.warnings = []
        info.warningsFetchedAt = now
        info.train = TrainStatus(state: .delayed, message: "", fetchedAt: now)
        XCTAssertEqual(info.currentWarnings(at: now.addingTimeInterval(1799)), [])
        XCTAssertNotNil(info.currentTrain(at: now.addingTimeInterval(1799)))
        XCTAssertNil(info.currentWarnings(at: now.addingTimeInterval(1800)))
        XCTAssertNil(info.currentTrain(at: now.addingTimeInterval(1800)))
        XCTAssertNil(info.currentWarnings(at: now.addingTimeInterval(-1)))
        XCTAssertNil(info.currentTrain(at: now.addingTimeInterval(-1)))
        info.warningsFetchedAt = nil
        XCTAssertNil(info.currentWarnings(at: now))
    }

    func testUVLevels() {
        XCTAssertEqual(UVLevel.text(2.4), "低")
        XCTAssertEqual(UVLevel.text(5), "中")
        XCTAssertEqual(UVLevel.text(7), "高")
        XCTAssertEqual(UVLevel.text(9), "甚高")
        XCTAssertEqual(UVLevel.text(12), "極高")
    }

    func testCurrentUVIsNotAForecastMaximum() throws {
        let json = #"{"icon":[51],"uvindex":{"data":[{"place":"京士柏","value":6.4,"desc":"高"}],"recordDesc":"過去一小時"}}"#
        let current = try HKOWeather.parseCurrent(Data(json.utf8))
        let snapshot = try XCTUnwrap(HKOWeather.snapshot(current: current, forecast: nil))
        XCTAssertEqual(snapshot.uvIndex, 6.4)
        XCTAssertTrue(snapshot.forecast.isEmpty)
    }

    func testExchangeRates() throws {
        let json = #"{"result":"success","rates":{"HKD":1,"JPY":19.31,"CNY":0.92,"TWD":4.1,"GBP":0.098,"XXX":3}}"#
        let rates = try FXAPI.parse(Data(json.utf8))
        XCTAssertEqual(rates.jpy, 19.31)
        XCTAssertEqual(rates.perHKD.count, 4)
        XCTAssertThrowsError(try FXAPI.parse(Data(#"{"result":"error"}"#.utf8)))
        XCTAssertThrowsError(try FXAPI.parse(Data(#"{"result":"success","rates":{"CNY":0.9}}"#.utf8)))
    }

    func testWeekSummary() {
        func day(_ kind: DutyDay.Kind, hours: Double? = nil) -> DutyDay {
            var day = DutyDay(date: "2026-10-26", code: "X", kind: kind, title: "X")
            day.hours = hours
            return day
        }
        let summary = WeekSummary.make([day(.duty, hours: 8), day(.duty, hours: 7.5), day(.spare, hours: 7), day(.rest), day(.rest), day(.leave), day(.pending)])
        XCTAssertEqual(summary, WeekSummary(workDays: 3, hours: 22.5, rest: 2, leave: 1, pending: 1))
        XCTAssertEqual(summary.text, "3 日 · 22.5 小時 · 休 2 · 假 1 · 待 1")
        XCTAssertEqual(WeekSummary.make([day(.duty, hours: 8), day(.rest)]).text, "1 日 · 8 小時 · 休 1")
    }
}
