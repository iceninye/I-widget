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

    func testAirQuality() throws {
        let air = try OpenMeteoAir.parse(Data(#"{"current":{"us_aqi":42.4,"pm2_5":11.2}}"#.utf8))
        XCTAssertEqual(air.aqi, 42)
        XCTAssertEqual(air.level, "良好")
        XCTAssertFalse(air.isPoor)
        XCTAssertEqual(AirQuality(aqi: 120, pm25: nil, fetchedAt: Date()).level, "敏感族群不宜")
        XCTAssertTrue(AirQuality(aqi: 120, pm25: nil, fetchedAt: Date()).isPoor)
        XCTAssertThrowsError(try OpenMeteoAir.parse(Data(#"{"current":{}}"#.utf8)))
    }

    func testUVLevels() {
        XCTAssertEqual(UVLevel.text(2.4), "低")
        XCTAssertEqual(UVLevel.text(5), "中")
        XCTAssertEqual(UVLevel.text(7), "高")
        XCTAssertEqual(UVLevel.text(9), "甚高")
        XCTAssertEqual(UVLevel.text(12), "極高")
    }

    func testUVInWeatherParse() throws {
        let json = #"{"current":{"temperature_2m":26},"daily":{"weather_code":[1,2],"temperature_2m_max":[28,29],"temperature_2m_min":[24,25],"precipitation_probability_max":[10,20],"uv_index_max":[6.4,7.1]}}"#
        let snapshot = try OpenMeteo.parse(Data(json.utf8))
        XCTAssertEqual(snapshot.today.uvIndex, 6.4)
        XCTAssertEqual(snapshot.tomorrow?.uvIndex, 7.1)
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
