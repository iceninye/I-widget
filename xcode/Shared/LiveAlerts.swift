import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

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
    var index: String
    var level: String
    var station: String
    /// EPD RSS item publication time; no finer observation timestamp is supplied.
    var observedAt: Date?
    var fetchedAt: Date

    var isPoor: Bool { index == "10+" || (Int(index) ?? 0) >= 7 }

    func isStale(at now: Date) -> Bool {
        guard let observedAt else { return true }
        return observedAt > now || now.timeIntervalSince(observedAt) >= 90 * 60
    }

    static let sample = AirQuality(index: "4", level: "中", station: "中西區（一般監測站）", observedAt: Date(), fetchedAt: Date())
}

enum EPDAQHI {
    static let url = URL(string: "https://www.aqhi.gov.hk/epd/ddata/html/out/aqhi_ind_rss_ChT.xml")!
    static let station = "中西區"
    static let cacheKey = "epd.aqhi.central-western.general.v1"

    static func riskLevel(_ index: String) -> String? {
        switch index {
        case "1", "2", "3": return "低"
        case "4", "5", "6": return "中"
        case "7": return "高"
        case "8", "9", "10": return "甚高"
        case "10+": return "嚴重"
        default: return nil
        }
    }

    static func parse(_ data: Data, station: String = station, now: Date = Date()) throws -> AirQuality {
        guard data.count <= 1_000_000,
              let xml = String(data: data, encoding: .utf8),
              !xml.localizedCaseInsensitiveContains("<!DOCTYPE"),
              !xml.localizedCaseInsensitiveContains("<!ENTITY") else { throw URLError(.cannotParseResponse) }
        let reader = RSSReader()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = reader
        guard parser.parse(), reader.isRSS else { throw URLError(.cannotParseResponse) }
        let pattern = "^" + NSRegularExpression.escapedPattern(for: station)
            + #"\s*-\s*一般監測站\s*[:：]\s*(10\+|10|[1-9])\s+(低|中|高|甚高|嚴重)(?:\s|$)"#
        let regex = try NSRegularExpression(pattern: pattern)
        for item in reader.items where item.title == station {
            let text = item.description.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let indexRange = Range(match.range(at: 1), in: text),
                  let riskRange = Range(match.range(at: 2), in: text) else { continue }
            let index = String(text[indexRange])
            guard let level = riskLevel(index), level == String(text[riskRange]) else { continue }
            let formatter = HKODate.formatter("EEE, dd MMM yyyy HH:mm:ss Z")
            return AirQuality(index: index, level: level, station: "\(station)（一般監測站）",
                              observedAt: formatter.date(from: item.pubDate), fetchedAt: now)
        }
        throw URLError(.cannotParseResponse)
    }

    private final class RSSReader: NSObject, XMLParserDelegate {
        struct Item {
            var title = ""
            var description = ""
            var pubDate = ""
        }
        var items: [Item] = []
        var isRSS = false
        private var path: [String] = []
        private var item: Item?
        private var text = ""

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) {
            path.append(elementName)
            if path == ["rss"] { isRSS = true }
            if path == ["rss", "channel", "item"] { item = Item() }
            text = ""
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            text += String(data: CDATABlock, encoding: .utf8) ?? ""
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            if path.count == 4, Array(path.prefix(3)) == ["rss", "channel", "item"] {
                let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
                switch elementName {
                case "title": item?.title = value
                case "description": item?.description = value
                case "pubDate": item?.pubDate = value
                default: break
                }
            }
            if path == ["rss", "channel", "item"], let item {
                items.append(item)
                self.item = nil
            }
            path.removeLast()
            text = ""
        }
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
