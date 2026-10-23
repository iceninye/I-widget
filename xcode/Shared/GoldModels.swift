import Foundation

struct GoldQuote: Codable, Equatable {
    var usdPerOunce: Double
    var fetchedAt: Date

    static let sample = GoldQuote(usdPerOunce: 2345.67, fetchedAt: Date())
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
