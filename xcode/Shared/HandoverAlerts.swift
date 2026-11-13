import Foundation

/// 更份卡一段行程：`[類別, Run, 接班地點, 接班時間, 離班地點, 離班時間]`（TML-traffic `data/duties/DS????.json` 嘅 `legs`）。
/// 時間係服務日 00:00 起計嘅秒數，過咗午夜會超過 86400。
struct DutyLeg: Codable, Equatable {
    /// drive、empty、park、prep、ride、wait …
    var kind: String
    var run: Int
    var from: String
    var at: Int
    var to: String
    var until: Int?

    init(kind: String, run: Int, from: String, at: Int, to: String, until: Int?) {
        self.kind = kind
        self.run = run
        self.from = from
        self.at = at
        self.to = to
        self.until = until
    }

    init?(raw: [Any]) {
        guard raw.count >= 5, let kind = raw[0] as? String,
              let run = (raw[1] as? NSNumber)?.intValue,
              let at = (raw[3] as? NSNumber)?.intValue else { return nil }
        self.kind = kind
        self.run = run
        self.from = raw[2] as? String ?? ""
        self.at = at
        self.to = raw[4] as? String ?? ""
        self.until = raw.count > 5 ? (raw[5] as? NSNumber)?.intValue : nil
    }

    /// 要揸住架車嘅類別（`ride` 係搭車、`wait` 係等，唔使交接）。
    var isTrain: Bool { Relief.trainKinds.contains(kind) }
}

/// 交接對象：邊個更、幾點、喺邊個月台。
struct DutyRelief: Codable, Equatable {
    var id: String
    var at: Int
    var place: String
}

/// 某段行程：邊個將車交俾你（from），你落車之後交俾邊個（to）。
struct LegRelief: Codable, Equatable {
    var from: DutyRelief?
    var to: DutyRelief?

    static let none = LegRelief(from: nil, to: nil)
}

/// 接車／交車，同 tml-roster `lib/tml-duties.js` 嘅 `reliefOf` 一致：
/// 同一張 Duty Sheet、同一個 Run、同一個站（錦上路1、2 當同一站），
/// 對方嗰段喺你開始前 20 分鐘內完結（接車），或者喺你完結後 20 分鐘內開始（交車）。
/// 自己上一段／下一段仍然係同一個 Run（例如出車準備之後直接開），就唔算交接。
enum Relief {
    static let window = 20 * 60
    static let trainKinds: Set<String> = ["drive", "empty", "park", "prep"]

    /// 「KSR1」→「KSR」；唔係「三個字母＋一個數字」就照用。
    static func station(_ place: String) -> String {
        place.range(of: "^[A-Z]{3}[0-9]$", options: .regularExpression) == nil ? place : String(place.prefix(3))
    }

    /// 呢段幾時完結：有離班時間就用，否則下一段開始，再唔係就放工。
    static func end(of legs: [DutyLeg], at index: Int, off: Int?) -> Int? {
        legs[index].until ?? (index + 1 < legs.count ? legs[index + 1].at : off)
    }

    static func continuesIn(_ legs: [DutyLeg], _ index: Int) -> Bool {
        index > 0 && legs[index - 1].run == legs[index].run && legs[index - 1].isTrain
    }

    static func continuesOut(_ legs: [DutyLeg], _ index: Int) -> Bool {
        index + 1 < legs.count && legs[index + 1].run == legs[index].run && legs[index + 1].isTrain
    }

    static func of(id: String, legs: [DutyLeg], off: Int?, index: Int, others: [(id: String, legs: [DutyLeg])]) -> LegRelief {
        guard index < legs.count, legs[index].isTrain else { return .none }
        let leg = legs[index]
        let until = end(of: legs, at: index, off: off)
        let checkIn = !continuesIn(legs, index)
        let checkOut = !continuesOut(legs, index)
        var take: DutyRelief?
        var hand: DutyRelief?
        for other in others where other.id != id {
            for l in other.legs where l.run == leg.run && l.isTrain {
                if checkIn, let otherEnd = l.until, station(l.to) == station(leg.from),
                   otherEnd <= leg.at + 60, leg.at - otherEnd <= window {
                    if take == nil || otherEnd > take!.at { take = DutyRelief(id: other.id, at: otherEnd, place: l.to) }
                }
                if checkOut, let until, l.kind != "prep", station(l.from) == station(leg.to),
                   l.at >= until - 60, l.at - until <= window {
                    if hand == nil || l.at < hand!.at { hand = DutyRelief(id: other.id, at: l.at, place: l.from) }
                }
            }
        }
        return LegRelief(from: take, to: hand)
    }
}

/// 提示設定：每種情況提前幾多分鐘（0 = 唔提），同語音讀出嘅設定。存喺 app 嘅 UserDefaults。
struct HandoverSettings: Codable, Equatable {
    /// 上班前（兩次，例如 1 小時前同 15 分鐘前）
    var onFirst = 60
    var onSecond = 15
    /// 接車前
    var pickUp = 15
    /// 落地／交車前
    var dropOff = 15
    /// 用膳完結（用膳後第一程接車）前
    var mealEnd = 15
    /// 放工前最後一次落地／交車前
    var lastDrop = 15
    /// 放工前
    var off = 0
    /// 通知一響就讀出內容
    var speak = true
    /// 聲線 identifier；nil = 自動揀廣東話
    var voice: String?
    /// 語速（AVSpeechUtterance：0–1，預設 0.5）
    var rate = 0.5
    /// 讀兩次（嘈吵環境）
    var twice = false

    static let key = "settings.handover"

    init() {}

    /// 之後加新欄位，舊設定都照樣讀到。
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        func int(_ key: CodingKeys, _ fallback: Int) -> Int {
            max(0, (try? values.decodeIfPresent(Int.self, forKey: key)) ?? fallback)
        }
        onFirst = int(.onFirst, 60)
        onSecond = int(.onSecond, 15)
        pickUp = int(.pickUp, 15)
        dropOff = int(.dropOff, 15)
        mealEnd = int(.mealEnd, 15)
        lastDrop = int(.lastDrop, 15)
        off = int(.off, 0)
        speak = (try? values.decodeIfPresent(Bool.self, forKey: .speak)) ?? true
        voice = (try? values.decodeIfPresent(String.self, forKey: .voice)) ?? nil
        rate = min(0.65, max(0.3, (try? values.decodeIfPresent(Double.self, forKey: .rate)) ?? 0.5))
        twice = (try? values.decodeIfPresent(Bool.self, forKey: .twice)) ?? false
    }

    static func load(_ defaults: UserDefaults = .standard) -> HandoverSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(HandoverSettings.self, from: data) else { return HandoverSettings() }
        return settings
    }

    func save(_ defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key) }
    }
}

/// 一個提示：幾時響、講咩。通知內容喺排程嗰陣已經定咗，所以只用 Duty Sheet 嘅時間。
struct HandoverAlert: Equatable {
    enum Kind: String { case on, pickUp = "pick", dropOff = "drop", off }

    var id: String
    var kind: Kind
    var fireAt: Date
    /// 返工／接車／落地／放工嘅時間
    var eventAt: Date
    var title: String
    var body: String
    /// body 去走「N 分鐘後」之後嘅內容（Live Activity 倒數用）
    var detail = ""
}

/// 由更份砌出當日全部提示（提前幾耐跟 `HandoverSettings`，預設全部 15 分鐘，上班另加 1 小時前）：
/// - 上班前：「1 小時後返工，08:53 喺錦上路，111 更」
/// - 接車前：「15 分鐘後你要喺錦上路 2接 128 更嘅 Run 18，開去烏溪沙」
/// - 落地前：「15 分鐘後喺錦上路 2落地，接你嗰位係 118 更，之後用膳到 11:16」
/// 每個提示都講埋之後做咩：用膳、泊車、接另一架車、搭車、收工。
enum HandoverAlerts {
    static let idPrefix = "handover."

    /// 「8027118」→「118」：同一張 Duty Sheet 入面，大家講後面三個字。
    static func short(_ id: String) -> String {
        id.count == 7 ? String(id.suffix(3)) : id
    }

    /// 服務日（`YYYY-MM-DD`）00:00 香港時間起計嘅秒數 → 實際時間。
    static func moment(date: String, second: Int) -> Date? {
        guard let day = Days.number(date) else { return nil }
        return Date(timeIntervalSince1970: Double(day) * 86_400 - 8 * 3_600 + Double(second))
    }

    /// 「15 分鐘後」「1 小時後」「1 小時 30 分鐘後」
    static func leadText(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) 分鐘後" }
        return minutes % 60 == 0 ? "\(minutes / 60) 小時後" : "\(minutes / 60) 小時 \(minutes % 60) 分鐘後"
    }

    /// 同一個 Run 連續幾段（例如準備 → 開車 → 泊車）當一程：由 `index` 開始，最後一段嘅位置。
    static func chainEnd(_ legs: [DutyLeg], from index: Int) -> Int {
        var last = index
        while Relief.continuesOut(legs, last) { last += 1 }
        return last
    }

    /// 落地之後做咩：用膳、收工，或者下一段行程。
    static func afterText(card: DutyCard, legs: [DutyLeg], index: Int, until: Int, places: PlaceNames) -> String {
        let next = index + 1 < legs.count ? legs[index + 1] : nil
        if let meal = card.meal, meal.start >= until - 60, next.map({ $0.at >= meal.start }) ?? true {
            return "之後用膳" + (meal.end.map { "到 \(DutyDay.clock($0))" } ?? "")
        }
        guard let next else { return "之後收工" }
        let at = DutyDay.clock(next.at)
        switch next.kind {
        case "ride": return "之後搭車去\(places.name(next.to))"
        case "wait": return "之後待命"
        case "park": return "之後 \(at) 喺\(places.name(next.from))泊車，Run \(next.run)"
        case "prep": return "之後 \(at) 喺\(places.name(next.from))準備 Run \(next.run)"
        case "drive", "empty": return "之後 \(at) 喺\(places.name(next.from))接 Run \(next.run)"
        default: return ""
        }
    }

    /// 接車、落地嘅提示（要有更份卡嘅行程）。
    static func make(card: DutyCard, date: String, places: PlaceNames, settings: HandoverSettings = HandoverSettings()) -> [HandoverAlert] {
        guard let legs = card.legs, !legs.isEmpty else { return [] }
        let reliefs = card.reliefs ?? []
        // 用膳之後第一段要接車嘅行程：跟「用膳完結前」嘅設定
        let firstAfterMeal = card.meal?.end.flatMap { end in
            legs.indices.first { legs[$0].isTrain && !Relief.continuesIn(legs, $0) && legs[$0].at >= end - 60 }
        }
        // 放工前最後一次落地
        let lastDrop = legs.indices.last(where: { legs[$0].isTrain && !Relief.continuesOut(legs, $0) })

        var result: [HandoverAlert] = []
        for index in legs.indices where legs[index].isTrain {
            let leg = legs[index]
            let relief = index < reliefs.count ? reliefs[index] : .none

            let pickLead = index == firstAfterMeal ? settings.mealEnd : settings.pickUp
            if pickLead > 0, !Relief.continuesIn(legs, index), let eventAt = moment(date: date, second: leg.at) {
                let place = places.name(leg.from)
                let last = chainEnd(legs, from: index)
                let chain = legs[index...last]
                let destination = places.name(legs[last].to)
                let whose = relief.from.map { short($0.id) + " 更嘅 " } ?? ""
                var body = ""
                switch leg.kind {
                case "prep":
                    body += "喺\(place)準備 Run \(leg.run)"
                    if last > index { body += "，之後開去\(destination)" }
                case "park":
                    body += "你要喺\(place)接 \(whose)Run \(leg.run)，泊車去\(destination)"
                default:
                    body += "你要喺\(place)接 \(whose)Run \(leg.run)"
                    body += leg.kind == "empty" ? "，空車去\(destination)" : "，開去\(destination)"
                    if chain.dropFirst().contains(where: { $0.kind == "park" }) { body += "，之後泊車" }
                }
                result.append(HandoverAlert(
                    id: "\(idPrefix)\(date).\(card.id).\(index).\(HandoverAlert.Kind.pickUp.rawValue)",
                    kind: .pickUp,
                    fireAt: eventAt.addingTimeInterval(-Double(pickLead * 60)),
                    eventAt: eventAt,
                    title: "接車 \(DutyDay.clock(leg.at)) · Run \(leg.run)",
                    body: leadText(pickLead) + body,
                    detail: body
                ))
            }

            let dropLead = index == lastDrop ? settings.lastDrop : settings.dropOff
            if dropLead > 0, !Relief.continuesOut(legs, index), let until = Relief.end(of: legs, at: index, off: card.off),
               let eventAt = moment(date: date, second: until) {
                let place = places.name(leg.to)
                let prefix = (index == lastDrop ? "最後一程，" : "") + leadText(dropLead)
                var body = ""
                if let to = relief.to {
                    body += "喺\(place)落地，接你嗰位係 \(short(to.id)) 更"
                } else if leg.kind == "park" {
                    body += "喺\(place)泊好車，Run \(leg.run)"
                } else {
                    body += "喺\(place)落地，Run \(leg.run)"
                }
                let after = afterText(card: card, legs: legs, index: index, until: until, places: places)
                if !after.isEmpty { body += "，\(after)" }
                result.append(HandoverAlert(
                    id: "\(idPrefix)\(date).\(card.id).\(index).\(HandoverAlert.Kind.dropOff.rawValue)",
                    kind: .dropOff,
                    fireAt: eventAt.addingTimeInterval(-Double(dropLead * 60)),
                    eventAt: eventAt,
                    title: "落地 \(DutyDay.clock(until)) · \(place)",
                    body: prefix + body,
                    detail: body
                ))
            }
        }
        return result.sorted { $0.fireAt < $1.fireAt }
    }

    /// 上班前（最多兩次）同放工前嘅提示：有上下班時間就得，唔使更份卡。
    static func dutyAlerts(day: DutyDay, settings: HandoverSettings = HandoverSettings()) -> [HandoverAlert] {
        var result: [HandoverAlert] = []
        let name = day.kind == .duty && day.code.count == 7 ? "\(short(day.code)) 更" : day.code
        if let on = day.on, let eventAt = moment(date: day.date, second: on) {
            let place = day.onPlace.isEmpty ? "" : " 喺\(day.onPlace)"
            for lead in Set([settings.onFirst, settings.onSecond]).sorted(by: >) where lead > 0 {
                result.append(HandoverAlert(
                    id: "\(idPrefix)\(day.date).\(day.code).on.\(lead)",
                    kind: .on,
                    fireAt: eventAt.addingTimeInterval(-Double(lead * 60)),
                    eventAt: eventAt,
                    title: "返工 \(DutyDay.clock(on))\(day.onPlace.isEmpty ? "" : " · \(day.onPlace)")",
                    body: "\(leadText(lead))返工，\(DutyDay.clock(on))\(place)，\(name)",
                    detail: "返工，\(DutyDay.clock(on))\(place)，\(name)"
                ))
            }
        }
        if settings.off > 0, let off = day.off, let eventAt = moment(date: day.date, second: off) {
            let place = day.offPlace.isEmpty ? "" : " 喺\(day.offPlace)"
            result.append(HandoverAlert(
                id: "\(idPrefix)\(day.date).\(day.code).off",
                kind: .off,
                fireAt: eventAt.addingTimeInterval(-Double(settings.off * 60)),
                eventAt: eventAt,
                title: "放工 \(DutyDay.clock(off))\(day.offPlace.isEmpty ? "" : " · \(day.offPlace)")",
                body: "\(leadText(settings.off))收工，\(DutyDay.clock(off))\(place)",
                detail: "收工，\(DutyDay.clock(off))\(place)"
            ))
        }
        return result
    }
}
