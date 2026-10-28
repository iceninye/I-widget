import Foundation

struct RegionalConditions: Codable, Equatable {
    var windStation: String?
    var windSpeed: Double?
    var windDirection: String?
    var gust: Double?
    var pressureStation: String?
    var pressure: Double?
    var windObservedAt: Date?
    var pressureObservedAt: Date?
    var fetchedAt: Date = Date()

    static func merged(wind: RegionalConditions?, pressure: RegionalConditions?) -> RegionalConditions? {
        guard let fetchedAt = [wind?.fetchedAt, pressure?.fetchedAt].compactMap({ $0 }).max() else { return nil }
        return RegionalConditions(windStation: wind?.windStation, windSpeed: wind?.windSpeed,
                                  windDirection: wind?.windDirection, gust: wind?.gust,
                                  pressureStation: pressure?.pressureStation, pressure: pressure?.pressure,
                                  windObservedAt: wind?.windObservedAt, pressureObservedAt: pressure?.pressureObservedAt,
                                  fetchedAt: fetchedAt)
    }

    static let sample = RegionalConditions(windStation: "京士柏", windSpeed: 12, windDirection: "東", gust: 24,
                                          pressureStation: "香港天文台", pressure: 1019.7,
                                          windObservedAt: Date(), pressureObservedAt: Date())
}

struct SunTimes: Codable, Equatable {
    var date: String
    var sunrise: String
    var sunset: String

    func isValid(on date: Date) -> Bool { self.date == HKODate.dayKey(date) }

    static var sample: SunTimes { SunTimes(date: HKODate.dayKey(Date()), sunrise: "06:26", sunset: "17:47") }
}

enum HKORegional {
    static let windURL = URL(string: "https://data.weather.gov.hk/weatherAPI/hko_data/regional-weather/latest_10min_wind_uc.csv")!
    static let pressureURL = URL(string: "https://data.weather.gov.hk/weatherAPI/hko_data/regional-weather/latest_1min_pressure_uc.csv")!
    static let windCacheKey = "hko.regional-wind.kings-park.v1"
    static let pressureCacheKey = "hko.regional-pressure.observatory.v1"

    // Wind/gust: km/h; mean sea-level pressure: hPa. Each file carries its own timestamp.
    static func parseWind(_ data: Data, now: Date = Date()) throws -> RegionalConditions {
        let row = try stationRow(data, station: "京士柏", columns: ["十分鐘平均風向（方位點）", "十分鐘平均風速（公里/小時）", "十分鐘最高陣風風速（公里/小時）"])
        guard let at = HKODate.parse(row["日期時間"], format: "yyyyMMddHHmm") else { throw URLError(.cannotParseResponse) }
        return RegionalConditions(windStation: "京士柏",
                                  windSpeed: number(row["十分鐘平均風速（公里/小時）"]),
                                  windDirection: CSV.value(row["十分鐘平均風向（方位點）"]),
                                  gust: number(row["十分鐘最高陣風風速（公里/小時）"]),
                                  windObservedAt: at, fetchedAt: now)
    }

    static func parsePressure(_ data: Data, now: Date = Date()) throws -> RegionalConditions {
        let row = try stationRow(data, station: "天文台", columns: ["平均海平面氣壓（百帕斯卡）"])
        guard let at = HKODate.parse(row["日期時間"], format: "yyyyMMddHHmm") else { throw URLError(.cannotParseResponse) }
        let pressure = number(row["平均海平面氣壓（百帕斯卡）"]).flatMap { $0 > 0 ? $0 : nil }
        return RegionalConditions(pressureStation: "香港天文台", pressure: pressure, pressureObservedAt: at, fetchedAt: now)
    }

    private static func number(_ value: String?) -> Double? {
        guard let text = CSV.value(value), let number = Double(text), number.isFinite, number >= 0 else { return nil }
        return number
    }

    private static func stationRow(_ data: Data, station: String, columns: [String]) throws -> [String: String] {
        let rows = try CSV.rows(data)
        guard let header = rows.first,
              Set(header).count == header.count,
              (["日期時間", "自動氣象站"] + columns).allSatisfy({ header.contains($0) }),
              let stationColumn = header.firstIndex(of: "自動氣象站"),
              let row = rows.dropFirst().first(where: { $0.count == header.count && $0[stationColumn] == station }) else {
            throw URLError(.cannotParseResponse)
        }
        return Dictionary(uniqueKeysWithValues: zip(header, row))
    }
}

struct HKOSolarYear: Codable, Equatable {
    var year: Int
    var days: [SunTimes]
    var fetchedAt: Date

    func day(on date: Date) -> SunTimes? {
        guard HKODate.calendar.component(.year, from: date) == year else { return nil }
        return days.first { $0.isValid(on: date) }
    }
}

enum HKOSolar {
    static func url(year: Int) -> URL {
        URL(string: "https://data.weather.gov.hk/weatherAPI/opendata/opendata.php?dataType=SRS&year=\(year)&rformat=csv")!
    }

    static func cacheKey(year: Int) -> String { "hko.sunrise-sunset.\(year).v1" }

    static func parse(_ data: Data, year: Int, now: Date = Date()) throws -> HKOSolarYear {
        let rows = try CSV.rows(data)
        guard let header = rows.first,
              let dateColumn = header.firstIndex(of: "YYYY-MM-DD"),
              let riseColumn = header.firstIndex(of: "RISE"),
              let setColumn = header.firstIndex(of: "SET") else { throw URLError(.cannotParseResponse) }
        var days: [SunTimes] = []
        for row in rows.dropFirst() {
            guard row.count == header.count,
                  let date = HKODate.parse(row[dateColumn], format: "yyyy-MM-dd"),
                  HKODate.calendar.component(.year, from: date) == year,
                  validTime(row[riseColumn]), validTime(row[setColumn]),
                  !days.contains(where: { $0.date == row[dateColumn] }) else { continue }
            days.append(SunTimes(date: row[dateColumn], sunrise: row[riseColumn], sunset: row[setColumn]))
        }
        guard !days.isEmpty else { throw URLError(.cannotParseResponse) }
        return HKOSolarYear(year: year, days: days.sorted { $0.date < $1.date }, fetchedAt: now)
    }

    private static func validTime(_ text: String) -> Bool {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].count == 2, parts[1].count == 2,
              parts.allSatisfy({ $0.allSatisfy({ $0.isASCII && $0.isNumber }) }),
              let hour = Int(parts[0]), let minute = Int(parts[1]) else { return false }
        return (0...23).contains(hour) && (0...59).contains(minute)
    }
}

// RFC-style quoted fields, escaped quotes and UTF-8 BOM; no positional CSV splitting.
enum CSV {
    static func value(_ text: String?) -> String? {
        guard let value = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty, !value.allSatisfy({ $0 == "-" }),
              !["N/A", "NA", "NULL"].contains(value.uppercased()) else { return nil }
        return value
    }

    static func rows(_ data: Data) throws -> [[String]] {
        guard data.count <= 2_000_000, var text = String(data: data, encoding: .utf8) else { throw URLError(.cannotParseResponse) }
        if text.first == "\u{FEFF}" { text.removeFirst() }
        text = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var closed = false
        let characters = Array(text)
        var index = 0
        func finishField() {
            row.append(field.trimmingCharacters(in: .whitespacesAndNewlines))
            field = ""
            closed = false
        }
        func finishRow() {
            finishField()
            if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
            row = []
        }
        while index < characters.count {
            let character = characters[index]
            if quoted {
                if character == "\"" {
                    if index + 1 < characters.count, characters[index + 1] == "\"" {
                        field.append("\"")
                        index += 1
                    } else {
                        quoted = false
                        closed = true
                    }
                } else { field.append(character) }
            } else {
                switch character {
                case ",": finishField()
                case "\n": finishRow()
                case "\"":
                    guard field.isEmpty, !closed else { throw URLError(.cannotParseResponse) }
                    quoted = true
                default:
                    if closed {
                        guard character == " " || character == "\t" else { throw URLError(.cannotParseResponse) }
                    } else { field.append(character) }
                }
            }
            index += 1
        }
        guard !quoted else { throw URLError(.cannotParseResponse) }
        finishRow()
        guard !rows.isEmpty else { throw URLError(.cannotParseResponse) }
        return rows
    }
}
