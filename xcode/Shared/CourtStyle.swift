import SwiftUI

extension CourtCategory {
    /// 分類顏色：widget 行頭色條、app 標籤同分類統計共用。
    var color: Color {
        switch self {
        case .criminal: return .red
        case .civil: return .blue
        case .family: return .purple
        case .appeal: return .orange
        case .tribunal: return .teal
        case .inquest: return .gray
        case .other: return .secondary
        }
    }
}
