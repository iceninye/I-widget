import Foundation

struct GoldQuote: Codable, Equatable {
    var usdPerOunce: Double
    var fetchedAt: Date

    static let sample = GoldQuote(usdPerOunce: 2345.67, fetchedAt: Date())

    /// 1 金衡盎司 = 31.1035 克；香港 1 両 = 37.429 克。
    static let gramsPerOunce = 31.1035
    static let gramsPerTael = 37.429
    /// 冇美元匯率（未讀到或者舊快取）時用嘅聯繫匯率中間價：1 美元 = 7.8 港元。
    static let pegHKDPerUSD = 7.8

    /// 港元價：用 open.er-api.com 嘅匯率（1 港元 = 幾多美元）換算；
    /// 冇匯率就用聯繫匯率 7.8，`estimated` = true 畀畫面提示。
    func hkd(rates: ExchangeRates?) -> GoldHKD {
        let usdPerHKD = rates?.perHKD["USD"].flatMap { $0 > 0 ? $0 : nil }
        let hkdPerUSD = usdPerHKD.map { 1 / $0 } ?? Self.pegHKDPerUSD
        let perOunce = usdPerOunce * hkdPerUSD
        return GoldHKD(
            perOunce: perOunce,
            perGram: perOunce / Self.gramsPerOunce,
            perTael: perOunce / Self.gramsPerOunce * Self.gramsPerTael,
            estimated: usdPerHKD == nil
        )
    }
}

/// 國際現貨金價換算做港元（每盎司、每克、每両）。
struct GoldHKD: Equatable {
    var perOunce: Double
    var perGram: Double
    var perTael: Double
    /// true = 用咗聯繫匯率 7.8 代替實時美元匯率
    var estimated: Bool
}

/// gold-api.com 嘅現貨 XAU/USD（國際參考價，唔係香港金舖零售價）。
enum GoldAPI {
    static let url = URL(string: "https://api.gold-api.com/price/XAU")!

    private struct Response: Decodable { let price: Double }

    static func parse(_ data: Data, now: Date = Date()) throws -> GoldQuote {
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard response.price > 0 else { throw URLError(.cannotParseResponse) }
        return GoldQuote(usdPerOunce: response.price, fetchedAt: now)
    }
}
