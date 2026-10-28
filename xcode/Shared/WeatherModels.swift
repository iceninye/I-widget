import Foundation

struct WeatherDay: Codable, Equatable {
    var date: String
    var code: Int
    var minTemp: Double
    var maxTemp: Double
    var rainChance: String?
    var wind: String
    var summary: String
}

struct WeatherSnapshot: Codable, Equatable {
    var currentTemp: Double?
    var currentCode: Int?
    var humidity: Double?
    var uvIndex: Double?
    var station: String
    var observedAt: Date?
    var forecast: [WeatherDay]
    var forecastUpdatedAt: Date?
    var fetchedAt: Date

    func day(on date: Date) -> WeatherDay? {
        let key = HKODate.dayKey(date)
        return forecast.first { $0.date == key }
    }

    static var sample: WeatherSnapshot {
        let now = Date()
        return WeatherSnapshot(
            currentTemp: 26, currentCode: 51, humidity: 71, uvIndex: 6,
            station: HKOWeather.station, observedAt: now,
            forecast: [WeatherDay(date: HKODate.dayKey(now), code: 51, minTemp: 25, maxTemp: 29,
                                  rainChance: "低", wind: "東風4至5級。", summary: "部分時間有陽光。")],
            forecastUpdatedAt: now, fetchedAt: now
        )
    }
}

// Current and forecast are cached independently; a failed endpoint cannot erase the other.
struct HKOCurrentWeather: Codable, Equatable {
    var currentTemp: Double?
    var currentCode: Int?
    var humidity: Double?
    var uvIndex: Double?
    var station: String
    var observedAt: Date?
    var fetchedAt: Date
}

struct HKOForecast: Codable, Equatable {
    var days: [WeatherDay]
    var updatedAt: Date?
    var fetchedAt: Date
}

enum HKODate {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Hong_Kong")!
        return calendar
    }

    static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        formatter.isLenient = false
        return formatter
    }

    static func dayKey(_ date: Date) -> String { formatter("yyyy-MM-dd").string(from: date) }

    static func parse(_ value: String?, format: String) -> Date? {
        guard let value else { return nil }
        let formatter = formatter(format)
        guard let date = formatter.date(from: value), formatter.string(from: date) == value else { return nil }
        return date
    }

    static func iso(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions.insert(.withFractionalSeconds)
        return formatter.date(from: value)
    }
}

enum HKOWeather {
    static let station = "香港天文台"
    static let currentURL = URL(string: "https://data.weather.gov.hk/weatherAPI/opendata/weather.php?dataType=rhrread&lang=tc")!
    static let forecastURL = URL(string: "https://data.weather.gov.hk/weatherAPI/opendata/weather.php?dataType=fnd&lang=tc")!
    static let currentCacheKey = "hko.rhrread.observatory.v1"
    static let forecastCacheKey = "hko.fnd9day.v1"

    private struct Measurement: Decodable {
        var place: String
        var value: Double?
    }

    private struct Readings: Decodable {
        var data: [Measurement]
        var recordTime: String?
    }

    private struct CurrentResponse: Decodable {
        var temperature: Readings?
        var humidity: Readings?
        var icon: [Int]?
        var uvindex: Readings?

        enum CodingKeys: String, CodingKey { case temperature, humidity, icon, uvindex }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            temperature = try values.decodeIfPresent(Readings.self, forKey: .temperature)
            humidity = try values.decodeIfPresent(Readings.self, forKey: .humidity)
            icon = try values.decodeIfPresent([Int].self, forKey: .icon)
            // HKO publishes an empty string at night, not a zero UV reading.
            uvindex = try? values.decode(Readings.self, forKey: .uvindex)
        }
    }

    static func parseCurrent(_ data: Data, now: Date = Date()) throws -> HKOCurrentWeather {
        let response = try JSONDecoder().decode(CurrentResponse.self, from: data)
        let temperature = response.temperature?.data.first { $0.place == station }?.value
        let humidity = response.humidity?.data.first { $0.place == station }?.value
        let uv = response.uvindex?.data.first { $0.place == "京士柏" }?.value
        let code = response.icon?.first
        guard temperature != nil || humidity != nil || code != nil else { throw URLError(.cannotParseResponse) }
        return HKOCurrentWeather(
            currentTemp: temperature, currentCode: code,
            humidity: humidity.flatMap { (0...100).contains($0) ? $0 : nil },
            uvIndex: uv.flatMap { $0 >= 0 ? $0 : nil }, station: station,
            observedAt: HKODate.iso(response.temperature?.recordTime) ?? HKODate.iso(response.humidity?.recordTime),
            fetchedAt: now
        )
    }

    static func parseForecast(_ data: Data, now: Date = Date()) throws -> HKOForecast {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = root["weatherForecast"] as? [[String: Any]] else { throw URLError(.cannotParseResponse) }
        struct Row: Decodable {
            struct Temperature: Decodable { var value: Double }
            var forecastDate: String
            var ForecastIcon: Int
            var forecastMintemp: Temperature
            var forecastMaxtemp: Temperature
            var forecastWind: String
            var forecastWeather: String
        }
        var days: [WeatherDay] = []
        for row in rows {
            guard let rowData = try? JSONSerialization.data(withJSONObject: row),
                  let value = try? JSONDecoder().decode(Row.self, from: rowData),
                  let date = HKODate.parse(value.forecastDate, format: "yyyyMMdd"),
                  value.forecastMintemp.value <= value.forecastMaxtemp.value else { continue }
            let key = HKODate.dayKey(date)
            guard !days.contains(where: { $0.date == key }) else { continue }
            let psr = (row["PSR"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            // PSR is categorical. Do not invent a percentage from a category.
            let categories = ["低", "中低", "中", "中高", "高"]
            days.append(WeatherDay(date: key, code: value.ForecastIcon,
                                   minTemp: value.forecastMintemp.value, maxTemp: value.forecastMaxtemp.value,
                                   rainChance: psr.flatMap { categories.contains($0) ? $0 : nil },
                                   wind: value.forecastWind, summary: value.forecastWeather))
        }
        guard !days.isEmpty else { throw URLError(.cannotParseResponse) }
        return HKOForecast(days: days.sorted { $0.date < $1.date }, updatedAt: HKODate.iso(root["updateTime"] as? String), fetchedAt: now)
    }

    static func snapshot(current: HKOCurrentWeather?, forecast: HKOForecast?) -> WeatherSnapshot? {
        guard let fetchedAt = [current?.fetchedAt, forecast?.fetchedAt].compactMap({ $0 }).max() else { return nil }
        return WeatherSnapshot(currentTemp: current?.currentTemp, currentCode: current?.currentCode,
                               humidity: current?.humidity, uvIndex: current?.uvIndex,
                               station: current?.station ?? station, observedAt: current?.observedAt,
                               forecast: forecast?.days ?? [], forecastUpdatedAt: forecast?.updatedAt, fetchedAt: fetchedAt)
    }
}

/// HKO icon numbers, not WMO weather codes.
enum WeatherCode {
    static func symbol(_ code: Int) -> String {
        switch code {
        case 50: return "sun.max.fill"
        case 51, 52: return "cloud.sun.fill"
        case 53, 54: return "cloud.sun.rain.fill"
        case 60, 61: return "cloud.fill"
        case 62: return "cloud.drizzle.fill"
        case 63: return "cloud.rain.fill"
        case 64: return "cloud.heavyrain.fill"
        case 65: return "cloud.bolt.rain.fill"
        case 70...75: return "moon.stars.fill"
        case 76, 77: return "cloud.moon.fill"
        case 80: return "wind"
        case 81: return "sun.haze.fill"
        case 82: return "humidity.fill"
        case 83, 84: return "cloud.fog.fill"
        case 85: return "sun.haze.fill"
        case 90, 91: return "thermometer.sun.fill"
        case 92, 93: return "thermometer.snowflake"
        default: return "questionmark.circle"
        }
    }

    static func text(_ code: Int) -> String {
        switch code {
        case 50: return "陽光充沛"
        case 51: return "間有陽光"
        case 52: return "短暫陽光"
        case 53: return "間有陽光幾陣驟雨"
        case 54: return "短暫陽光有驟雨"
        case 60: return "多雲"
        case 61: return "密雲"
        case 62: return "微雨"
        case 63: return "雨"
        case 64: return "大雨"
        case 65: return "雷暴"
        case 70...75: return "天色良好"
        case 76: return "大致多雲"
        case 77: return "天色大致良好"
        case 80: return "大風"
        case 81: return "乾燥"
        case 82: return "潮濕"
        case 83: return "霧"
        case 84: return "薄霧"
        case 85: return "煙霞"
        case 90: return "熱"
        case 91: return "暖"
        case 92: return "涼"
        case 93: return "冷"
        default: return "天氣不明"
        }
    }
}
