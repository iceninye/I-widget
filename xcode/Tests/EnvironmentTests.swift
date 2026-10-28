import XCTest

final class EnvironmentTests: XCTestCase {
    private let wind = """
    日期時間,自動氣象站,十分鐘平均風向（方位點）,十分鐘平均風速（公里/小時）,十分鐘最高陣風風速（公里/小時）
    202610282220,中環碼頭,東南,22,38
    202610282220,京士柏,東,12,24
    202610282220,屯門,東南,10,24
    """
    private let pressure = """
    日期時間,自動氣象站,平均海平面氣壓（百帕斯卡）
    202610282230,赤鱲角,1019.2
    202610282230,天文台,1019.7
    """
    private let solar = """
    YYYY-MM-DD,RISE,TRAN.,SET
    2026-01-01,07:03,12:27,17:51
    2026-01-02,07:03,12:27,17:51
    2026-10-28,06:25,12:07,17:49
    2026-10-29,06:26,12:07,17:48
    """

    func testRegionalStationSelectionUnitsAndSeparateObservationTimes() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let wind = try HKORegional.parseWind(Data(wind.utf8), now: now)
        let pressure = try HKORegional.parsePressure(Data(pressure.utf8), now: now)
        let result = try XCTUnwrap(RegionalConditions.merged(wind: wind, pressure: pressure))
        XCTAssertEqual(result.windStation, "京士柏")
        XCTAssertEqual(result.windSpeed, 12)
        XCTAssertEqual(result.windDirection, "東")
        XCTAssertEqual(result.gust, 24)
        XCTAssertEqual(result.pressureStation, "香港天文台")
        XCTAssertEqual(result.pressure, 1019.7)
        XCTAssertEqual(result.windObservedAt, HKODate.iso("2026-10-28T22:20:00+08:00"))
        XCTAssertEqual(result.pressureObservedAt, HKODate.iso("2026-10-28T22:30:00+08:00"))
        XCTAssertEqual(result.fetchedAt, now)
    }

    func testRegionalPartialFailureDoesNotInventZeroOrOtherStation() throws {
        let wind = try HKORegional.parseWind(Data(wind.utf8))
        let result = try XCTUnwrap(RegionalConditions.merged(wind: wind, pressure: nil))
        XCTAssertEqual(result.windSpeed, 12)
        XCTAssertNil(result.pressure)
        XCTAssertNil(result.pressureStation)
        XCTAssertNil(result.pressureObservedAt)
        XCTAssertNil(RegionalConditions.merged(wind: nil, pressure: nil))
        XCTAssertThrowsError(try HKORegional.parseWind(Data(self.wind.replacingOccurrences(of: "京士柏", with: "另一站").utf8)))
        XCTAssertThrowsError(try HKORegional.parsePressure(Data(pressure.replacingOccurrences(of: "天文台", with: "另一站").utf8)))
    }

    func testCSVHandlesBOMQuotedCommasEscapedQuotesAndNewlines() throws {
        let csv = "\u{FEFF}station,value,note\r\n\"A, B\",\"12\",\"a \"\"quoted\"\"\r\nline\"\r\n"
        XCTAssertEqual(try CSV.rows(Data(csv.utf8)), [["station", "value", "note"], ["A, B", "12", "a \"quoted\"\nline"]])
        let quoted = "\u{FEFF}" + wind.replacingOccurrences(of: "京士柏", with: "\"京士柏\"")
        XCTAssertEqual(try HKORegional.parseWind(Data(quoted.utf8)).windSpeed, 12)
        for value in ["\"unterminated", "a,\"b\"x", "a,b\"c", ""] {
            XCTAssertThrowsError(try CSV.rows(Data(value.utf8)))
        }
        XCTAssertThrowsError(try CSV.rows(Data([0xFF, 0xFF])))
    }

    func testSentinelsAndMalformedNumbersStayMissing() throws {
        for missing in ["----", "N/A", "", "NaN", "bad", "-1"] {
            let value = wind.replacingOccurrences(of: "京士柏,東,12,24", with: "京士柏,----,\(missing),----")
            let reading = try HKORegional.parseWind(Data(value.utf8))
            XCTAssertNil(reading.windSpeed)
            XCTAssertNil(reading.windDirection)
            XCTAssertNil(reading.gust)
            XCTAssertEqual(reading.windStation, "京士柏")
            let pressure = self.pressure.replacingOccurrences(of: "1019.7", with: missing)
            XCTAssertNil(try HKORegional.parsePressure(Data(pressure.utf8)).pressure)
        }
        let calm = wind.replacingOccurrences(of: "京士柏,東,12,24", with: "京士柏,無風,0,0")
        XCTAssertEqual(try HKORegional.parseWind(Data(calm.utf8)).windSpeed, 0)
        XCTAssertNil(try HKORegional.parsePressure(Data(pressure.replacingOccurrences(of: "1019.7", with: "0").utf8)).pressure)
    }

    func testMalformedRegionalCSVAndTimestampAreRejected() {
        for value in ["<html>unavailable</html>", "日期時間,自動氣象站\n202610282220,京士柏", ""] {
            XCTAssertThrowsError(try HKORegional.parseWind(Data(value.utf8)))
            XCTAssertThrowsError(try HKORegional.parsePressure(Data(value.utf8)))
        }
        XCTAssertThrowsError(try HKORegional.parseWind(Data(wind.replacingOccurrences(of: "202610282220", with: "202602302220").utf8)))
    }

    func testAnnualSolarSelectsHongKongDateAcrossMidnight() throws {
        let year = try HKOSolar.parse(Data(solar.utf8), year: 2026)
        let beforeMidnight = try XCTUnwrap(HKODate.iso("2026-10-28T15:59:59Z"))
        let midnight = try XCTUnwrap(HKODate.iso("2026-10-28T16:00:00Z"))
        let today = try XCTUnwrap(year.day(on: beforeMidnight))
        XCTAssertEqual(today.date, "2026-10-28")
        XCTAssertEqual(today.sunrise, "06:25")
        XCTAssertEqual(today.sunset, "17:49")
        XCTAssertFalse(today.isValid(on: midnight))
        XCTAssertEqual(year.day(on: midnight)?.date, "2026-10-29")
        XCTAssertEqual(year.day(on: midnight)?.sunrise, "06:26")
        XCTAssertNil(year.day(on: midnight.addingTimeInterval(86_400)))
    }

    func testSolarYearCacheCannotReturnPreviousYearOrMissingDay() throws {
        let year = try HKOSolar.parse(Data(solar.utf8), year: 2026)
        let nextYear = try XCTUnwrap(HKODate.iso("2026-12-31T16:00:00Z"))
        XCTAssertNil(year.day(on: nextYear))
        XCTAssertNotEqual(HKOSolar.cacheKey(year: 2026), HKOSolar.cacheKey(year: 2027))
        XCTAssertTrue(HKOSolar.url(year: 2026).absoluteString.contains("dataType=SRS&year=2026&rformat=csv"))
        XCTAssertThrowsError(try HKOSolar.parse(Data(solar.utf8), year: 2027))
    }

    func testSolarQuotesBOMAndMalformedRows() throws {
        let valid = "\u{FEFF}YYYY-MM-DD,RISE,TRAN.,SET\r\n\"2026-10-28\",\"06:25\",12:07,\"17:49\"\r\n"
        let invalid = "2026-10-29,----,12:07,17:49\n2026-10-30,25:00,12:07,17:49\n2026-02-30,06:00,12:07,17:49\n2026-11-01,06:00,12:07,18:99\n"
        XCTAssertEqual(try HKOSolar.parse(Data((valid + invalid).utf8), year: 2026).days.count, 1)
        XCTAssertThrowsError(try HKOSolar.parse(Data("YYYY-MM-DD,RISE,TRAN.,SET\n2026-10-28,----,12:07,----".utf8), year: 2026))
        XCTAssertThrowsError(try HKOSolar.parse(Data("<html>unavailable</html>".utf8), year: 2026))
    }
}
