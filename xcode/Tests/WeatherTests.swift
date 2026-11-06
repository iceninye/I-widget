import XCTest

final class WeatherTests: XCTestCase {
    private let sample = """
    {"current":{"temperature_2m":26.4},
     "daily":{"time":["2026-10-23","2026-10-24"],
              "weather_code":[3,61],
              "temperature_2m_max":[28.1,27.0],
              "temperature_2m_min":[24.0,23.2],
              "precipitation_probability_max":[20,70]}}
    """

    func testParseTodayAndTomorrow() throws {
        let snapshot = try OpenMeteo.parse(Data(sample.utf8))
        XCTAssertEqual(snapshot.currentTemp, 26.4)
        XCTAssertEqual(snapshot.today.maxTemp, 28.1)
        XCTAssertEqual(snapshot.today.code, 3)
        XCTAssertEqual(snapshot.today.rainChance, 20)
        XCTAssertEqual(snapshot.tomorrow?.code, 61)
        XCTAssertEqual(snapshot.tomorrow?.rainChance, 70)
    }

    func testParseSingleDayHasNoTomorrow() throws {
        let json = #"{"daily":{"weather_code":[0],"temperature_2m_max":[30],"temperature_2m_min":[25]}}"#
        let snapshot = try OpenMeteo.parse(Data(json.utf8))
        XCTAssertNil(snapshot.tomorrow)
        XCTAssertNil(snapshot.currentTemp)
        XCTAssertNil(snapshot.today.rainChance)
    }

    func testParseWithoutTodayThrows() {
        let json = #"{"daily":{"weather_code":[],"temperature_2m_max":[],"temperature_2m_min":[]}}"#
        XCTAssertThrowsError(try OpenMeteo.parse(Data(json.utf8)))
        XCTAssertThrowsError(try OpenMeteo.parse(Data("{}".utf8)))
    }

    func testURLContainsCoordinates() throws {
        let url = try XCTUnwrap(OpenMeteo.url(latitude: 22.3193, longitude: 114.1694))
        XCTAssertTrue(url.absoluteString.contains("latitude=22.319"))
        XCTAssertTrue(url.absoluteString.contains("longitude=114.169"))
        XCTAssertTrue(url.absoluteString.contains("forecast_days=7"))
        XCTAssertTrue(url.absoluteString.contains("hourly=temperature_2m"))
    }

    func testParseWeekAndHourly() throws {
        let json = """
        {"daily":{"time":["2026-11-06","2026-11-07"],"weather_code":[3,61],
                  "temperature_2m_max":[26,24],"temperature_2m_min":[20,19],
                  "precipitation_probability_max":[10,80]},
         "hourly":{"time":["2026-11-06T07:00","2026-11-06T08:00","2026-11-06T15:00"],
                   "temperature_2m":[21.4,22.0,25.6],
                   "precipitation_probability":[5,null,40],
                   "weather_code":[2,3,61]}}
        """
        let snapshot = try OpenMeteo.parse(Data(json.utf8))
        XCTAssertEqual(snapshot.days?.count, 2)
        XCTAssertEqual(snapshot.day("2026-11-07")?.rainChance, 80)
        XCTAssertNil(snapshot.day("2026-11-08"))
        XCTAssertEqual(snapshot.hours?.count, 3)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Hong_Kong")!
        let at = calendar.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 15, minute: 40))!
        let hour = try XCTUnwrap(snapshot.hour(at: at, calendar: calendar))
        XCTAssertEqual(hour.temp, 25.6)
        XCTAssertEqual(hour.rainChance, 40)
        XCTAssertEqual(hour.code, 61)
        let eight = calendar.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 8))!
        XCTAssertNil(snapshot.hour(at: eight, calendar: calendar)?.rainChance)
        XCTAssertNil(snapshot.hour(at: calendar.date(byAdding: .day, value: 3, to: at)!, calendar: calendar))
    }

    func testOldCacheWithoutForecastStillDecodes() throws {
        let old = WeatherSnapshot(currentTemp: 20, today: WeatherDay(code: 0, minTemp: 18, maxTemp: 24), tomorrow: nil, fetchedAt: Date(timeIntervalSince1970: 0))
        // 舊版快取根本冇 days／hours 兩個 key
        let json = try XCTUnwrap(String(data: JSONEncoder().encode(old), encoding: .utf8))
        XCTAssertFalse(json.contains("days"))
        let decoded = try JSONDecoder().decode(WeatherSnapshot.self, from: Data(json.utf8))
        XCTAssertNil(decoded.days)
        XCTAssertNil(decoded.hours)
        XCTAssertEqual(decoded.today.maxTemp, 24)
    }

    func testWeatherCodeMapping() {
        XCTAssertEqual(WeatherCode.text(0), "晴")
        XCTAssertEqual(WeatherCode.symbol(61), "cloud.rain.fill")
        XCTAssertEqual(WeatherCode.symbol(95), "cloud.bolt.rain.fill")
        XCTAssertEqual(WeatherCode.symbol(999), "cloud.fill")
    }

    func testFormatting() {
        XCTAssertEqual(Formatting.degrees(26.6), "27°")
        XCTAssertEqual(Formatting.degrees(nil), Formatting.missing)
        XCTAssertEqual(Formatting.tempRange(WeatherDay(code: 0, minTemp: 23.6, maxTemp: 28.2, rainChance: nil)), "24–28°")
        XCTAssertEqual(Formatting.tempRange(nil), Formatting.missing)
    }
}
