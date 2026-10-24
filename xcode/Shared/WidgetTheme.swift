import Foundation

/// 完整彩色模式嘅風格預設。撳右上角嘅調色掣按次序轉。
/// Clear／Tinted 模式由 iOS 用玻璃材質同使用者揀嘅色調畫，唔受呢個影響。
enum WidgetTheme: String, Codable, CaseIterable {
    case classic, ocean, sunset, forest, violet, mono

    var label: String {
        switch self {
        case .classic: return "預設"
        case .ocean: return "海藍"
        case .sunset: return "日落"
        case .forest: return "森林"
        case .violet: return "紫羅蘭"
        case .mono: return "單色"
        }
    }

    var next: WidgetTheme {
        let all = Self.allCases
        guard let index = all.firstIndex(of: self) else { return .classic }
        return all[(index + 1) % all.count]
    }
}
