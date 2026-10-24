import Foundation

/// TML-traffic 嘅更份卡（`data/duties/DS????.json`）：上落班、用膳、組別、工時。
/// 邏輯跟 tml-roster `assets/app.js` 嘅今日咭（cellInfo、sheetForDate、placeName），只讀。
struct DutySheet: Codable, Equatable {
    var code: String
    var file: String
    var special: Bool
    var dates: [String]
}

struct DutyMeal: Codable, Equatable {
    var start: Int
    var end: Int?
    var from: String
    var to: String?
}

struct DutyCard: Codable, Equatable {
    var id: String
    var group: String?
    var on: Int
    var onPlace: String
    var off: Int
    var offPlace: String
    /// 分鐘
    var work: Int?
    var meal: DutyMeal?
}

enum DutyData {
    static let bases = [
        "https://tml-traffic.iceninye.workers.dev/",
        "https://raw.githubusercontent.com/iceninye/TML-traffic/main/",
    ]

    static func urls(_ path: String) -> [URL] {
        bases.compactMap { URL(string: $0 + path) }
    }

    static func parseIndex(_ data: Data) throws -> [DutySheet] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sheets = root["sheets"] as? [[String: Any]] else { throw URLError(.cannotParseResponse) }
        return sheets.compactMap { sheet in
            guard let code = sheet["code"] as? String, let file = sheet["file"] as? String,
                  file.range(of: "^[A-Za-z0-9_.-]+\\.json$", options: .regularExpression) != nil else { return nil }
            let dates = (sheet["dates"] as? [String] ?? []) + (sheet["alsoOn"] as? [String] ?? [])
            return DutySheet(code: code, file: file, special: sheet["class"] as? String == "special", dates: dates)
        }
    }

    /// 只抽需要嘅更份，唔使成份 sheet 放入快取。
    static func parseCards(_ data: Data, ids: Set<String>) throws -> [String: DutyCard] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let duties = root["duties"] as? [[String: Any]] else { throw URLError(.cannotParseResponse) }
        var result: [String: DutyCard] = [:]
        for duty in duties {
            guard let id = duty["id"] as? String, ids.contains(id),
                  let on = duty["on"] as? [Any], let off = duty["off"] as? [Any],
                  let onAt = (on.first as? NSNumber)?.intValue, let offAt = (off.first as? NSNumber)?.intValue else { continue }
            var meal: DutyMeal?
            if let raw = duty["meal"] as? [Any], let start = (raw.first as? NSNumber)?.intValue {
                meal = DutyMeal(
                    start: start,
                    end: raw.count > 1 ? (raw[1] as? NSNumber)?.intValue : nil,
                    from: raw.count > 2 ? raw[2] as? String ?? "" : "",
                    to: raw.count > 3 ? raw[3] as? String : nil
                )
            }
            result[id] = DutyCard(
                id: id,
                group: duty["group"] as? String,
                on: onAt,
                onPlace: on.count > 1 ? on[1] as? String ?? "" : "",
                off: offAt,
                offPlace: off.count > 1 ? off[1] as? String ?? "" : "",
                work: (duty["work"] as? NSNumber)?.intValue,
                meal: meal
            )
        }
        return result
    }

    /// 某日嘅更份用邊份 Duty Sheet：通常係編號頭 4 位；特別日子嘅 sheet（例如 7091M）同平日共用編號。
    static func sheet(for code: String, date: String, sheets: [DutySheet]) -> String {
        let prefix = String(code.prefix(4))
        let dated = sheets.first { $0.code != prefix && $0.code.hasPrefix(prefix) && $0.dates.contains(date) }
        return dated?.code ?? prefix
    }

    /// 特別日提示：Roster 寫 6091124，但當日行 8022，就提示更份可能係 8022124（只提示，唔自動換）。
    static func specialHint(for code: String, date: String, sheets: [DutySheet]) -> String? {
        guard let special = sheets.first(where: { $0.special && $0.dates.contains(date) }),
              special.code != sheet(for: code, date: date, sheets: sheets) else { return nil }
        return "當日用 Duty Sheet \(special.code)，更份可能係 \(special.code.prefix(4))\(code.dropFirst(4))"
    }
}

/// 其他代碼（Ice 2026-10-22 定，同 tml-roster `lib/tml-extra.js` 一致）。
/// 開工日：工時（小時），部分有固定上下班（秒，由 00:00 起計）；假期：有薪工時（CL 係 0）。
enum ExtraCodes {
    struct Work: Equatable {
        var hours: Double
        var on: Int? = nil
        var off: Int? = nil
    }

    private static func at(_ hour: Int, _ minute: Int = 0) -> Int { (hour * 60 + minute) * 60 }

    static let work: [String: Work] = [
        "SPH7": Work(hours: 7), "SPL7": Work(hours: 7), "SPT7": Work(hours: 7), "SPT75": Work(hours: 7.5),
        "TRG": Work(hours: 7), "TRGK": Work(hours: 7), "TRGL": Work(hours: 7),
        "SLP": Work(hours: 7.5, on: at(15), off: at(23)),
        "SEP": Work(hours: 8, on: at(6, 45), off: at(15, 15)),
        "JCC": Work(hours: 7),
        "SPKE": Work(hours: 7.5, on: at(7), off: at(15)),
        "SPKL": Work(hours: 7.5, on: at(15), off: at(23)),
    ]

    static let off: [String: Double] = ["CL": 0, "CP": 7, "GH": 7, "PH": 7, "SH": 7, "SL": 7, "WB": 7]
}

/// 站代號 → 中文名（`data/tml-network.json` 嘅 stations 同 places）。
struct PlaceNames: Codable, Equatable {
    var stations: [String: String]
    var places: [String: String]

    static let empty = PlaceNames(stations: [:], places: [:])

    static let depots = [
        "TAD": "大圍廠", "HHS": "紅磡廠", "TT": "大圍廠", "W1A": "八鄉廠", "W1C": "八鄉廠", "W1F": "八鄉廠",
        "LT1": "紅磡廠", "LT2": "紅磡廠", "E3A": "錦上路", "E3C": "錦上路",
    ]

    static func parse(_ data: Data) throws -> PlaceNames {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw URLError(.cannotParseResponse) }
        func names(_ key: String) -> [String: String] {
            var result: [String: String] = [:]
            for (code, value) in root[key] as? [String: Any] ?? [:] {
                if let tc = (value as? [String: Any])?["tc"] as? String, !tc.isEmpty { result[code] = tc }
            }
            return result
        }
        let parsed = PlaceNames(stations: names("stations"), places: names("places"))
        guard !parsed.stations.isEmpty else { throw URLError(.cannotParseResponse) }
        return parsed
    }

    /// 「KSR2」= 錦上路 2 號月台；唔係站嘅代號照寫。
    func name(_ code: String) -> String {
        if code.isEmpty { return "—" }
        if let depot = Self.depots[code] { return "\(depot) \(code)" }
        if let place = places[code] { return place }
        var base = code
        if let last = code.last, last.isNumber { base = String(code.dropLast()) }
        guard let station = stations[base] else { return code }
        return base == code ? station : "\(station) \(code.dropFirst(base.count))"
    }
}

/// 某日更份嘅顯示內容（今日咭／明日一行）。
struct DutyDay: Equatable {
    enum Kind: Equatable { case duty, rest, leave, pending, spare, other }

    var date: String
    var code: String
    var kind: Kind
    var title: String
    var shift: ShiftClass?
    var group: String?
    /// 特別日子用另一份 sheet（例如 7091M）
    var datedSheet: String?
    var on: Int?
    var off: Int?
    var onPlace: String = ""
    var offPlace: String = ""
    var hours: Double?
    var mealStart: Int?
    var mealEnd: Int?
    var mealPlace: String?
    var hint: String?
    var isOverride = false

    /// 7 日色條用嘅短標籤：更類（死早、早、中、夜、死夜）、休、假、待。
    var shortLabel: String {
        switch kind {
        case .rest: return "休"
        case .leave: return "假"
        case .pending: return "待"
        case .spare: return "備"
        case .duty, .other: return shift?.rawValue ?? String(code.prefix(2))
        }
    }

    var hasTimes: Bool { on != nil && off != nil }

    var times: String? {
        guard let on, let off else { return nil }
        return "\(DutyDay.clock(on)) – \(DutyDay.clock(off))"
    }

    /// 同一個地點就唔寫兩次（避免「錦上路 → 錦上路」）。
    var route: String? {
        guard !onPlace.isEmpty || !offPlace.isEmpty else { return nil }
        return onPlace == offPlace || offPlace.isEmpty ? onPlace : "\(onPlace) → \(offPlace)"
    }

    var hoursText: String? {
        guard let hours, hours > 0 else { return nil }
        let rounded = (hours * 100).rounded() / 100
        return rounded == rounded.rounded() ? "\(Int(rounded)) 小時" : "\(rounded) 小時"
    }

    var mealText: String? {
        guard let mealStart else { return nil }
        let end = mealEnd.map { "–\(DutyDay.clock($0))" } ?? ""
        return "用膳 \(DutyDay.clock(mealStart))\(end)\(mealPlace.map { " \($0)" } ?? "")"
    }

    /// 服務日 04:00 起計嘅秒數 → 實際時間。
    func moment(atServiceSecond seconds: Int) -> Date? {
        guard let day = Days.number(date) else { return nil }
        // 服務日 0 秒 = 當日香港 00:00 = UTC 前一日 16:00
        return Date(timeIntervalSince1970: Double(day) * 86_400 - 8 * 3_600 + Double(seconds))
    }

    static func clock(_ seconds: Int) -> String {
        let hours = (seconds / 3_600) % 24
        let minutes = (seconds % 3_600) / 60
        return String(format: "%02d:%02d", hours, minutes)
    }

    static let statusNames = ["RD": "休息", "AL": "年假", "SH": "法定假日", "HC": "待定", "TBC": "待定"]

    static func make(
        roster: Roster,
        date: String,
        basic: [String: DutyTime],
        cards: [String: DutyCard],
        sheets: [DutySheet],
        places: PlaceNames
    ) -> DutyDay? {
        guard let entry = roster.entry(on: date) else { return nil }
        let code = entry.code
        var day = DutyDay(date: date, code: code, kind: .other, title: code, isOverride: entry.isOverride)

        if let name = statusNames[code] {
            day.kind = code == "RD" ? .rest : (code == "HC" || code == "TBC" ? .pending : .leave)
            day.title = name
            return day
        }

        if ExtraCodes.off[code] != nil {
            day.kind = .leave
            day.title = "\(code) 假期"
            return day
        }

        let isDuty = code.range(of: "^[0-9]{7}$", options: .regularExpression) != nil
        if isDuty {
            day.kind = .duty
            let sheet = DutyData.sheet(for: code, date: date, sheets: sheets)
            let dated = sheet != String(code.prefix(4))
            day.datedSheet = dated ? sheet : nil
            day.hint = DutyData.specialHint(for: code, date: date, sheets: sheets)
            if let card = cards[cardKey(sheet: sheet, id: code)] {
                day.group = card.group
                day.on = card.on
                day.off = card.off
                day.onPlace = places.name(card.onPlace)
                day.offPlace = places.name(card.offPlace)
                day.hours = card.work.map { Double($0) / 60 } ?? basic[code]?.hours
                if let meal = card.meal {
                    day.mealStart = meal.start
                    day.mealEnd = meal.end
                    let from = places.name(meal.from)
                    if let to = meal.to.map(places.name), to != from {
                        day.mealPlace = "\(from) → \(to)"
                    } else {
                        day.mealPlace = from
                    }
                }
            } else if !dated, let time = basic[code] {
                // 官表 basic 只係平日嗰份 sheet 嘅時間，特別日子唔用
                day.on = time.on
                day.off = time.off
                day.onPlace = time.onPlace
                day.offPlace = time.offPlace
                day.hours = time.hours
            }
        } else if let work = ExtraCodes.work[code] {
            // 開工日代碼：有固定時間就用表，否則用官表 duty-basic（地點一律用官表嘅）
            day.kind = .duty
            let time = basic[code]
            day.on = work.on ?? time?.on
            day.off = work.off ?? time?.off
            day.onPlace = time.map { places.name($0.onPlace) } ?? ""
            day.offPlace = time.map { places.name($0.offPlace) } ?? ""
            day.hours = work.hours
        } else if code.range(of: "^[HK]SP[0-9]?$", options: .regularExpression) != nil {
            day.kind = .spare
            if let time = basic[code] {
                day.on = time.on
                day.off = time.off
                day.onPlace = time.onPlace
                day.offPlace = time.offPlace
                day.hours = time.hours
            }
        } else if let time = basic[code] {
            day.on = time.on
            day.off = time.off
            day.onPlace = time.onPlace
            day.offPlace = time.offPlace
            day.hours = time.hours
        }

        if let on = day.on {
            day.shift = ShiftClass.of(on: on, off: day.off)
        }
        switch day.kind {
        case .duty: day.title = day.shift.map { "\($0.rawValue)更 \(code)" } ?? "更份 \(code)"
        case .spare: day.title = "後備更 \(code)"
        default: break
        }
        return day
    }

    static func cardKey(sheet: String, id: String) -> String { "\(sheet)/\(id)" }
}
