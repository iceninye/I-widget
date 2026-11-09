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

/// 一個交接提示：幾時響、講咩。通知內容喺排程嗰陣已經定咗，所以只用 Duty Sheet 嘅時間。
struct HandoverAlert: Equatable {
    enum Kind: String { case pickUp = "pick", dropOff = "drop" }

    var id: String
    var kind: Kind
    var fireAt: Date
    /// 接車／落地嘅時間
    var eventAt: Date
    var title: String
    var body: String
}

/// 由更份卡砌出當日全部交接提示：
/// - 落地前 5 分鐘：「5 分鐘後喺錦上路 1落地，接你嗰位係 118 更」
/// - 接車前 5 分鐘；用膳之後嘅第一程提前 15 分鐘：「15 分鐘後你要喺錦上路 2接 128 更嘅 Run 18」
enum HandoverAlerts {
    static let dropLead = 5 * 60
    static let pickLead = 5 * 60
    static let afterMealLead = 15 * 60
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

    private static func minutes(_ seconds: Int) -> String { "\(seconds / 60) 分鐘後" }

    static func make(card: DutyCard, date: String, places: PlaceNames) -> [HandoverAlert] {
        guard let legs = card.legs, !legs.isEmpty else { return [] }
        let reliefs = card.reliefs ?? []
        // 用膳之後第一段要接車嘅行程：用膳完結前 15 分鐘提
        let mealEnd = card.meal?.end
        let firstAfterMeal = mealEnd.flatMap { end in
            legs.indices.first { legs[$0].isTrain && !Relief.continuesIn(legs, $0) && legs[$0].at >= end - 60 }
        }

        var result: [HandoverAlert] = []
        for index in legs.indices where legs[index].isTrain {
            let leg = legs[index]
            let relief = index < reliefs.count ? reliefs[index] : .none

            if !Relief.continuesIn(legs, index), let eventAt = moment(date: date, second: leg.at) {
                let lead = index == firstAfterMeal ? afterMealLead : pickLead
                let place = places.name(leg.from)
                let body: String
                if leg.kind == "prep" {
                    body = "\(minutes(lead))喺\(place)準備 Run \(leg.run)"
                } else if let from = relief.from {
                    body = "\(minutes(lead))你要喺\(place)接 \(short(from.id)) 更嘅 Run \(leg.run)"
                } else {
                    body = "\(minutes(lead))你要喺\(place)接 Run \(leg.run)"
                }
                result.append(HandoverAlert(
                    id: "\(idPrefix)\(date).\(card.id).\(index).\(HandoverAlert.Kind.pickUp.rawValue)",
                    kind: .pickUp,
                    fireAt: eventAt.addingTimeInterval(-Double(lead)),
                    eventAt: eventAt,
                    title: "接車 \(DutyDay.clock(leg.at)) · Run \(leg.run)",
                    body: body
                ))
            }

            if !Relief.continuesOut(legs, index), let until = Relief.end(of: legs, at: index, off: card.off),
               let eventAt = moment(date: date, second: until) {
                let place = places.name(leg.to)
                let body: String
                if let to = relief.to {
                    body = "\(minutes(dropLead))喺\(place)落地，接你嗰位係 \(short(to.id)) 更"
                } else {
                    body = "\(minutes(dropLead))喺\(place)落地（Run \(leg.run)）"
                }
                result.append(HandoverAlert(
                    id: "\(idPrefix)\(date).\(card.id).\(index).\(HandoverAlert.Kind.dropOff.rawValue)",
                    kind: .dropOff,
                    fireAt: eventAt.addingTimeInterval(-Double(dropLead)),
                    eventAt: eventAt,
                    title: "落地 \(DutyDay.clock(until)) · \(place)",
                    body: body
                ))
            }
        }
        return result.sorted { $0.fireAt < $1.fireAt }
    }
}
