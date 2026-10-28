import XCTest

final class WeatherTests: XCTestCase {
    // Bounded rhrread/fnd fixtures based on the official 2026-10-28 responses.
    private let current = #"{"temperature":{"data":[{"place":"京士柏","value":25,"unit":"C"},{"place":"香港天文台","value":26,"unit":"C"}],"recordTime":"2026-10-28T22:00:00+08:00"},"humidity":{"data":[{"place":"香港天文台","value":71,"unit":"percent"}],"recordTime":"2026-10-28T22:00:00+08:00"},"icon":[60],"uvindex":"","updateTime":"2026-10-28T22:02:00+08:00"}"#
    private let forecast = #"{"weatherForecast":[{"forecastDate":"20261029","forecastWind":"東風4至5級，初時離岸及高地間中6級。","forecastWeather":"大致多雲，初時有一兩陣微雨。日間漸轉天晴及乾燥。","forecastMaxtemp":{"value":29,"unit":"C"},"forecastMintemp":{"value":25,"unit":"C"},"ForecastIcon":51,"PSR":"低"},{"forecastDate":"20261030","forecastWind":"東風3至4級。","forecastWeather":"天晴。日間乾燥。","forecastMaxtemp":{"value":30,"unit":"C"},"forecastMintemp":{"value":25,"unit":"C"},"ForecastIcon":50,"PSR":"低"}],"updateTime":"2026-10-28T16:30:00+08:00"}"#

    func testCurrentUsesNamedObservatoryAndSourceTime() throws {
        let now = try XCTUnwrap(HKODate.iso("2026-10-28T22:05:00+08:00"))
        let reading = try HKOWeather.parseCurrent(Data(current.utf8), now: now)
        XCTAssertEqual(reading.currentTemp, 26)
        XCTAssertEqual(reading.currentCode, 60)
        XCTAssertEqual(reading.humidity, 71)
        XCTAssertNil(reading.uvIndex)
        XCTAssertEqual(reading.station, "香港天文台")
        XCTAssertEqual(reading.observedAt, HKODate.iso("2026-10-28T22:00:00+08:00"))
        XCTAssertEqual(reading.fetchedAt, now)
        XCTAssertNotEqual(reading.observedAt, reading.fetchedAt)
    }

    func testCurrentUVObjectAndEmptyNightValue() throws {
        let day = current.replacingOccurrences(of: #""uvindex":"""#, with: #""uvindex":{"data":[{"place":"京士柏","value":6.4,"desc":"高"}],"recordDesc":"過去一小時"}"#)
        XCTAssertEqual(try HKOWeather.parseCurrent(Data(day.utf8)).uvIndex, 6.4)
        XCTAssertNil(try HKOWeather.parseCurrent(Data(current.utf8)).uvIndex)
        let zero = day.replacingOccurrences(of: "6.4", with: "0")
        XCTAssertEqual(try HKOWeather.parseCurrent(Data(zero.utf8)).uvIndex, 0)
        let malformed = current.replacingOccurrences(of: #""uvindex":"""#, with: #""uvindex":{"data":"unavailable"}"#)
        XCTAssertNil(try HKOWeather.parseCurrent(Data(malformed.utf8)).uvIndex)
    }

    func testForecastKeepsDatesAndCategoricalPSR() throws {
        let result = try HKOWeather.parseForecast(Data(forecast.utf8))
        XCTAssertEqual(result.days.map(\.date), ["2026-10-29", "2026-10-30"])
        XCTAssertEqual(result.days[0].code, 51)
        XCTAssertEqual(result.days[0].minTemp, 25)
        XCTAssertEqual(result.days[0].maxTemp, 29)
        XCTAssertEqual(result.days[0].rainChance, "低")
        XCTAssertTrue(result.days[0].wind.contains("東風"))
        XCTAssertTrue(result.days[0].summary.contains("大致多雲"))
        XCTAssertEqual(result.updatedAt, HKODate.iso("2026-10-28T16:30:00+08:00"))
        let numeric = forecast.replacingOccurrences(of: #""PSR":"低""#, with: #""PSR":"20%""#)
        XCTAssertNil(try HKOWeather.parseForecast(Data(numeric.utf8)).days[0].rainChance)
        let malformedPSR = forecast.replacingOccurrences(of: #""PSR":"低""#, with: #""PSR":20"#)
        XCTAssertNil(try HKOWeather.parseForecast(Data(malformedPSR.utf8)).days[0].rainChance)
    }

    func testTomorrowIsNeverRelabeledTodayAndUsesHongKongMidnight() throws {
        let snapshot = try XCTUnwrap(HKOWeather.snapshot(current: HKOWeather.parseCurrent(Data(current.utf8)), forecast: HKOWeather.parseForecast(Data(forecast.utf8))))
        let beforeMidnight = try XCTUnwrap(HKODate.iso("2026-10-28T15:59:59Z"))
        let midnight = try XCTUnwrap(HKODate.iso("2026-10-28T16:00:00Z"))
        XCTAssertNil(snapshot.day(on: beforeMidnight))
        XCTAssertEqual(snapshot.day(on: midnight)?.date, "2026-10-29")
        XCTAssertEqual(snapshot.day(on: midnight)?.code, 51)
        XCTAssertNil(snapshot.day(on: midnight.addingTimeInterval(3 * 86_400)))
    }

    func testCurrentAndForecastFragmentsCanFailIndependently() throws {
        let oldFetch = Date(timeIntervalSince1970: 1_000)
        let newFetch = Date(timeIntervalSince1970: 2_000)
        let reading = try HKOWeather.parseCurrent(Data(current.utf8), now: oldFetch)
        let prediction = try HKOWeather.parseForecast(Data(forecast.utf8), now: newFetch)
        let currentOnly = try XCTUnwrap(HKOWeather.snapshot(current: reading, forecast: nil))
        XCTAssertEqual(currentOnly.currentTemp, 26)
        XCTAssertEqual(currentOnly.forecast, [])
        XCTAssertEqual(currentOnly.fetchedAt, oldFetch)
        let forecastOnly = try XCTUnwrap(HKOWeather.snapshot(current: nil, forecast: prediction))
        XCTAssertNil(forecastOnly.currentTemp)
        XCTAssertNil(forecastOnly.currentCode)
        XCTAssertNil(forecastOnly.uvIndex)
        XCTAssertNil(forecastOnly.observedAt)
        XCTAssertEqual(forecastOnly.forecast.count, 2)
        let merged = try XCTUnwrap(HKOWeather.snapshot(current: reading, forecast: prediction))
        XCTAssertEqual(merged.observedAt, reading.observedAt)
        XCTAssertEqual(merged.forecastUpdatedAt, prediction.updatedAt)
        XCTAssertEqual(merged.fetchedAt, newFetch)
        XCTAssertNil(HKOWeather.snapshot(current: nil, forecast: nil))
    }

    func testMissingStationDoesNotUseAnotherStationsTemperature() throws {
        let missing = current.replacingOccurrences(of: "香港天文台", with: "屯門")
        let result = try HKOWeather.parseCurrent(Data(missing.utf8))
        XCTAssertNil(result.currentTemp)
        XCTAssertNil(result.humidity)
        XCTAssertEqual(result.currentCode, 60)
        XCTAssertEqual(result.station, "香港天文台")
    }

    func testMalformedResponsesAndDates() throws {
        for value in ["{}", "[]", "not JSON"] {
            XCTAssertThrowsError(try HKOWeather.parseCurrent(Data(value.utf8)))
            XCTAssertThrowsError(try HKOWeather.parseForecast(Data(value.utf8)))
        }
        XCTAssertThrowsError(try HKOWeather.parseForecast(Data(#"{"weatherForecast":[]}"#.utf8)))
        let badDate = forecast.replacingOccurrences(of: "20261029", with: "20260230")
        XCTAssertEqual(try HKOWeather.parseForecast(Data(badDate.utf8)).days.map(\.date), ["2026-10-30"])
        XCTAssertNil(HKODate.parse("2026-02-30", format: "yyyy-MM-dd"))
        let absentPSR = forecast.replacingOccurrences(of: ",\"PSR\":\"低\"", with: "")
        XCTAssertNil(try HKOWeather.parseForecast(Data(absentPSR.utf8)).days[0].rainChance)
    }

    func testOfficialURLsAndNewCacheNamespaces() {
        XCTAssertTrue(HKOWeather.currentURL.absoluteString.contains("dataType=rhrread"))
        XCTAssertTrue(HKOWeather.forecastURL.absoluteString.contains("dataType=fnd"))
        XCTAssertNotEqual(HKOWeather.currentCacheKey, "weather")
        XCTAssertNotEqual(HKOWeather.forecastCacheKey, HKOWeather.currentCacheKey)
    }

    func testHKOIconMappingIncludingUnknownCodes() {
        XCTAssertEqual(WeatherCode.text(50), "陽光充沛")
        XCTAssertEqual(WeatherCode.text(61), "密雲")
        XCTAssertEqual(WeatherCode.symbol(63), "cloud.rain.fill")
        XCTAssertEqual(WeatherCode.symbol(65), "cloud.bolt.rain.fill")
        XCTAssertEqual(WeatherCode.symbol(73), "moon.stars.fill")
        XCTAssertEqual(WeatherCode.text(93), "冷")
        XCTAssertEqual(WeatherCode.text(999), "天氣不明")
        XCTAssertEqual(WeatherCode.symbol(999), "questionmark.circle")
        XCTAssertEqual(WeatherCode.symbol(0), "questionmark.circle")
    }

    func testFormatting() {
        XCTAssertEqual(Formatting.degrees(26.6), "27°")
        XCTAssertEqual(Formatting.degrees(nil), Formatting.missing)
        let day = WeatherDay(date: "2026-10-28", code: 51, minTemp: 23.6, maxTemp: 28.2,
                             rainChance: nil, wind: "", summary: "")
        XCTAssertEqual(Formatting.tempRange(day), "24–28°")
        XCTAssertEqual(Formatting.tempRange(nil), Formatting.missing)
    }
}
