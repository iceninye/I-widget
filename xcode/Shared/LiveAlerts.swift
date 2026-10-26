import Foundation

/// 天文台現正生效嘅警告。
struct WeatherWarning: Codable, Equatable {
    var text: String
    /// 紅色／黑色暴雨、八號或以上風球
    var severe: Bool
}

/// 天文台開放數據 `warnsum`：冇警告就係 `{}`，否則每個警告一項。
enum HKOWarnings {
    static let url = URL(string: "https://data.weather.gov.hk/weatherAPI/opendata/weather.php?dataType=warnsum&lang=tc")!

    private static let named: [String: (String, Bool)] = [
        "WRAINA": ("黃色暴雨", false), "WRAINR": ("紅色暴雨", true), "WRAINB": ("黑色暴雨", true),
        "TC1": ("一號風球", false), "TC3": ("三號風球", false),
        "TC8NE": ("八號風球", true), "TC8SE": ("八號風球", true), "TC8NW": ("八號風球", true), "TC8SW": ("八號風球", true),
        "TC9": ("九號風球", true), "TC10": ("十號風球", true),
        "WFIREY": ("黃色火災危險", false), "WFIRER": ("紅色火災危險", true),
    ]

    static func parse(_ data: Data) throws -> [WeatherWarning] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw URLError(.cannotParseResponse)
        }
        var result: [WeatherWarning] = []
        for key in root.keys.sorted() {
            guard let item = root[key] as? [String: Any] else { continue }
            if (item["actionCode"] as? String)?.uppercased() == "CANCEL" { continue }
            let code = item["code"] as? String ?? key
            if let (text, severe) = named[code] {
                result.append(WeatherWarning(text: text, severe: severe))
            } else if let name = item["name"] as? String, !name.isEmpty {
                result.append(WeatherWarning(text: name, severe: false))
            }
        }
        return result
    }
}

enum TrainState: String, Codable {
    case normal, delayed, special

    var text: String {
        switch self {
        case .normal: return "正常"
        case .delayed: return "延誤"
        case .special: return "特別安排"
        }
    }
}

struct TrainStatus: Codable, Equatable {
    var state: TrainState
    var message: String
    var fetchedAt: Date

    static let sample = TrainStatus(state: .normal, message: "", fetchedAt: Date())
}

/// 港鐵 `getSchedule.php`（屯門站）：`isdelay` 係 Y 就係延誤；特別行車安排時 status 係 0，帶港鐵訊息。
enum MTRStatus {
    static let url = URL(string: "https://rt.data.gov.hk/v1/transport/mtr/getSchedule.php?line=TML&sta=TUM&lang=tc")!

    static func parse(_ data: Data, now: Date = Date()) throws -> TrainStatus {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw URLError(.cannotParseResponse)
        }
        let message = (root["message"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let usable = message.isEmpty || message == "-" || message.lowercased() == "successful" ? "" : message
        let status = (root["status"] as? NSNumber)?.intValue ?? (root["status"] as? String).flatMap(Int.init)
        if status == 0 {
            return TrainStatus(state: .special, message: usable, fetchedAt: now)
        }
        guard status == 1 else { throw URLError(.cannotParseResponse) }
        let delayed = (root["isdelay"] as? String) == "Y"
        return TrainStatus(state: delayed ? .delayed : .normal, message: usable, fetchedAt: now)
    }
}

struct AirQuality: Codable, Equatable {
    var aqi: Int
    var pm25: Double?
    var fetchedAt: Date

    static let sample = AirQuality(aqi: 42, pm25: 11, fetchedAt: Date())

    /// US AQI 分級。
    var level: String {
        switch aqi {
        case ..<51: return "良好"
        case ..<101: return "一般"
        case ..<151: return "敏感族群不宜"
        case ..<201: return "不健康"
        case ..<301: return "非常不健康"
        default: return "危險"
        }
    }

    var isPoor: Bool { aqi > 100 }
}

/// Open-Meteo 空氣質素：免費、免 key，跟位置。
enum OpenMeteoAir {
    static func url(latitude: Double, longitude: Double) -> URL? {
        var components = URLComponents(string: "https://air-quality-api.open-meteo.com/v1/air-quality")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.3f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.3f", longitude)),
            URLQueryItem(name: "current", value: "us_aqi,pm2_5"),
        ]
        return components?.url
    }

    private struct Response: Decodable {
        struct Current: Decodable {
            let us_aqi: Double?
            let pm2_5: Double?
        }
        let current: Current?
    }

    static func parse(_ data: Data, now: Date = Date()) throws -> AirQuality {
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard let aqi = response.current?.us_aqi else { throw URLError(.cannotParseResponse) }
        return AirQuality(aqi: Int(aqi.rounded()), pm25: response.current?.pm2_5, fetchedAt: now)
    }
}

/// 紫外線指數分級。
enum UVLevel {
    static func text(_ index: Double) -> String {
        switch index {
        case ..<3: return "低"
        case ..<6: return "中"
        case ..<8: return "高"
        case ..<11: return "甚高"
        default: return "極高"
        }
    }
}

/// 1 港元 = 幾多外幣。
struct ExchangeRates: Codable, Equatable {
    var perHKD: [String: Double]
    var fetchedAt: Date

    static let sample = ExchangeRates(
        perHKD: ["JPY": 19.3, "CNY": 0.92, "TWD": 4.1, "GBP": 0.098],
        fetchedAt: Date()
    )

    /// 日圓：1 港元兑幾多日圓。
    var jpy: Double? { perHKD["JPY"] }
}

/// open.er-api.com：免費、免 key，一日更新一次。
enum FXAPI {
    static let url = URL(string: "https://open.er-api.com/v6/latest/HKD")!
    static let codes = ["JPY", "CNY", "TWD", "GBP"]

    static func parse(_ data: Data, now: Date = Date()) throws -> ExchangeRates {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["result"] as? String == "success",
              let rates = root["rates"] as? [String: Any] else { throw URLError(.cannotParseResponse) }
        var picked: [String: Double] = [:]
        for code in codes {
            if let value = (rates[code] as? NSNumber)?.doubleValue, value > 0 { picked[code] = value }
        }
        guard picked["JPY"] != nil else { throw URLError(.cannotParseResponse) }
        return ExchangeRates(perHKD: picked, fetchedAt: now)
    }
}

/// 本週（星期一至日）概況：開工日、工時、休息、假期、待定。同 tml-roster「本週概況」一致。
struct WeekSummary: Equatable {
    var workDays = 0
    var hours = 0.0
    var rest = 0
    var leave = 0
    var pending = 0

    static func make(_ days: [DutyDay]) -> WeekSummary {
        var summary = WeekSummary()
        for day in days {
            switch day.kind {
            case .rest: summary.rest += 1
            case .leave: summary.leave += 1
            case .pending: summary.pending += 1
            case .duty, .spare, .other:
                summary.workDays += 1
                summary.hours += day.hours ?? 0
            }
        }
        return summary
    }

    var text: String {
        let rounded = (hours * 10).rounded() / 10
        let hoursText = rounded == rounded.rounded() ? "\(Int(rounded))" : "\(rounded)"
        var parts = ["\(workDays) 日", "\(hoursText) 小時", "休 \(rest)"]
        if leave > 0 { parts.append("假 \(leave)") }
        if pending > 0 { parts.append("待 \(pending)") }
        return parts.joined(separator: " · ")
    }
}
