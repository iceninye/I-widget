import Foundation

struct WeatherDay: Codable, Equatable {
    var code: Int
    var minTemp: Double
    var maxTemp: Double
    var rainChance: Int?
    var uvIndex: Double?
}

/// 某一日（`yyyy-MM-dd`，當地時間）嘅預報。
struct DatedWeather: Codable, Equatable {
    var date: String
    var day: WeatherDay
}

/// 某個鐘頭（`yyyy-MM-ddTHH:mm`，當地時間）嘅預報。
struct WeatherHour: Codable, Equatable {
    var time: String
    var temp: Double?
    var rainChance: Int?
    var code: Int?
}

struct WeatherSnapshot: Codable, Equatable {
    var currentTemp: Double?
    var today: WeatherDay
    var tomorrow: WeatherDay?
    var fetchedAt: Date
    /// 7 日預報；舊快取冇呢欄，解碼成 nil。
    var days: [DatedWeather]? = nil
    /// 逐小時預報；舊快取冇呢欄，解碼成 nil。
    var hours: [WeatherHour]? = nil

    /// `yyyy-MM-dd` 嗰日嘅預報（同更表嘅服務日格式一樣）。
    func day(_ date: String) -> WeatherDay? {
        days?.first { $0.date == date }?.day
    }

    /// 某一刻所屬鐘頭嘅預報；`calendar` 嘅時區要同預報一致（香港）。
    func hour(at date: Date, calendar: Calendar) -> WeatherHour? {
        let parts = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day, let hour = parts.hour else { return nil }
        let key = String(format: "%04d-%02d-%02dT%02d:00", year, month, day, hour)
        return hours?.first { $0.time == key }
    }

    static let sample = WeatherSnapshot(
        currentTemp: 26.4,
        today: WeatherDay(code: 3, minTemp: 24, maxTemp: 28, rainChance: 20, uvIndex: 6),
        tomorrow: WeatherDay(code: 61, minTemp: 23, maxTemp: 27, rainChance: 70),
        fetchedAt: Date()
    )
}

/// Open-Meteo：免費、免 key（非商業用途）。7 日預報加逐小時（今日咭用嚟睇返工／放工嗰陣嘅天氣）。
enum OpenMeteo {
    static func url(latitude: Double, longitude: Double) -> URL? {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.3f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.3f", longitude)),
            URLQueryItem(name: "current", value: "temperature_2m"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,uv_index_max"),
            URLQueryItem(name: "hourly", value: "temperature_2m,precipitation_probability,weather_code"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "7"),
        ]
        return components?.url
    }

    private struct Response: Decodable {
        struct Current: Decodable { let temperature_2m: Double? }
        struct Daily: Decodable {
            let time: [String]?
            let weather_code: [Double?]
            let temperature_2m_max: [Double?]
            let temperature_2m_min: [Double?]
            let precipitation_probability_max: [Double?]?
            let uv_index_max: [Double?]?
        }
        struct Hourly: Decodable {
            let time: [String]
            let temperature_2m: [Double?]?
            let precipitation_probability: [Double?]?
            let weather_code: [Double?]?
        }
        let current: Current?
        let daily: Daily
        let hourly: Hourly?
    }

    private static func value(_ list: [Double?]?, _ index: Int) -> Double? {
        guard let list, index < list.count else { return nil }
        return list[index]
    }

    static func parse(_ data: Data, now: Date = Date()) throws -> WeatherSnapshot {
        let response = try JSONDecoder().decode(Response.self, from: data)
        let daily = response.daily

        func day(_ index: Int) -> WeatherDay? {
            guard index < daily.weather_code.count,
                  index < daily.temperature_2m_max.count,
                  index < daily.temperature_2m_min.count,
                  let code = daily.weather_code[index],
                  let high = daily.temperature_2m_max[index],
                  let low = daily.temperature_2m_min[index] else { return nil }
            var rain: Int?
            if let chances = daily.precipitation_probability_max, index < chances.count, let value = chances[index] {
                rain = Int(value.rounded())
            }
            var uv: Double?
            if let values = daily.uv_index_max, index < values.count { uv = values[index] }
            return WeatherDay(code: Int(code), minTemp: low, maxTemp: high, rainChance: rain, uvIndex: uv)
        }

        guard let today = day(0) else { throw URLError(.cannotParseResponse) }
        var days: [DatedWeather]?
        if let times = daily.time {
            days = times.indices.compactMap { index in day(index).map { DatedWeather(date: times[index], day: $0) } }
        }
        var hours: [WeatherHour]?
        if let hourly = response.hourly {
            hours = hourly.time.indices.map { index in
                WeatherHour(
                    time: hourly.time[index],
                    temp: value(hourly.temperature_2m, index),
                    rainChance: value(hourly.precipitation_probability, index).map { Int($0.rounded()) },
                    code: value(hourly.weather_code, index).map { Int($0) }
                )
            }
        }
        return WeatherSnapshot(
            currentTemp: response.current?.temperature_2m, today: today, tomorrow: day(1), fetchedAt: now,
            days: days, hours: hours
        )
    }
}

/// WMO 天氣代碼 → SF Symbol 同中文。
enum WeatherCode {
    static func symbol(_ code: Int) -> String {
        switch code {
        case 0, 1: return "sun.max.fill"
        case 2: return "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55, 56, 57: return "cloud.drizzle.fill"
        case 61, 63, 66, 80, 81: return "cloud.rain.fill"
        case 65, 67, 82: return "cloud.heavyrain.fill"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow.fill"
        case 95, 96, 99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    static func text(_ code: Int) -> String {
        switch code {
        case 0: return "晴"
        case 1: return "大致晴朗"
        case 2: return "部分多雲"
        case 3: return "多雲"
        case 45, 48: return "霧"
        case 51, 53, 55, 56, 57: return "毛毛雨"
        case 61, 63, 66, 80, 81: return "有雨"
        case 65, 67, 82: return "大雨"
        case 71, 73, 75, 77, 85, 86: return "有雪"
        case 95, 96, 99: return "雷暴"
        default: return "天氣不明"
        }
    }
}
