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
        XCTAssertTrue(url.absoluteString.contains("forecast_days=2"))
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
