import Foundation

/// 開機太耐嘅提示：5 日轉黃，7 日建議重啟。純函式，方便單元測試。
enum RebootHint: Equatable {
    case none, soon, due

    static let soonAfter: TimeInterval = 5 * 86_400
    static let dueAfter: TimeInterval = 7 * 86_400

    static func level(uptime: TimeInterval?) -> RebootHint {
        guard let uptime, uptime >= 0 else { return .none }
        if uptime >= dueAfter { return .due }
        return uptime >= soonAfter ? .soon : .none
    }

    /// 接喺開機時間後面嘅字。
    var suffix: String {
        switch self {
        case .none: return ""
        case .soon: return " · 快要重啟"
        case .due: return " · 建議重啟"
        }
    }
}
