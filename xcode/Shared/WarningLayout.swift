import Foundation

/// 警告 badge 嘅排版（budget 計算＋收幾多條）純邏輯，抽咗出嚟先測到。
///
/// **所有寬度數值仍然係估算，未喺真機量過**（沙箱冇 Swift 工具鏈）。呢啲數值只決定
/// 「顯示幾多條警告、其餘寫成 +N 項」，唔決定內容對唔對：行本身有 `lineLimit(1)` 同
/// `minimumScaleFactor`，估大咗只會縮字，估細咗就會過早收埋（正正係之前 `.systemLarge`
/// 當同 `.systemMedium` 等闊導致嘅問題）。
///
/// 呢檔只 import Foundation，所以唔可以用 `WidgetFamily`（SwiftUI/WidgetKit 嘅類型）：
/// family → `Size` 嘅映射喺 `OverviewView` 做。
enum WarningLayout {

    /// widget 尺寸（淨用嚟估寬）。
    enum Size: CaseIterable {
        case small, medium, large, extraLarge, extraLargePortrait
        case rectangular, inline, circular
        /// 未知／iPad・Mac 大格：呢個先係最闊嗰檔，唔可以當一般 iPhone 尺寸
        case wide
    }

    /// 嗰個尺寸警告嗰行嘅內容可用闊（約數，已扣容器 padding）。
    ///
    /// 參考：medium（iPhone 4 列）內容約 300pt；large 約 2× medium；extraLarge／extraLargePortrait
    /// 都係闊有限、高先唔同；`wide` 係 iPad／Mac 嘅大格。
    /// 注意 iPhone 上 `.systemLarge` 嘅物理寬度其實同 medium 差唔多（佢係高咗一倍），
    /// 所以 `large` 呢個數係偏大嘅保守值：寧願縮字都唔好想當然收埋警告。未實測。
    static func rowWidth(_ size: Size) -> CGFloat {
        switch size {
        case .small: return 130
        case .medium: return 300
        case .large: return 600
        case .extraLarge: return 640
        case .extraLargePortrait: return 620
        case .rectangular: return 150
        case .inline: return 200
        case .circular: return 120
        case .wide: return 900
        }
    }

    /// 粗估一段字嘅闊：中文（CJK）一個字級，ASCII／數字約 0.55 個字級。
    static func text(_ string: String, size: CGFloat) -> CGFloat {
        var width: CGFloat = 0
        for scalar in string.unicodeScalars {
            width += scalar.value >= 0x2E80 ? size : size * 0.55
        }
        return width
    }

    /// Badge 嘅估計闊：文字（10pt）＋左右 padding 5+5＋同前面元素嘅 spacing 5。
    static func badgeWidth(_ string: String) -> CGFloat { text(string, size: 10) + 15 }

    /// 行內 `padding(.horizontal, 4)` 兩邊
    static let rowPadding: CGFloat = 8
    /// 警告圖標連 spacing
    static let iconWidth: CGFloat = 22
    /// 「+N 項」要留嘅位
    static let overflowWidth: CGFloat = 36

    /// 警告 badge 得返幾闊：行闊扣 padding、圖標、屯馬綫 badge（如有）同可能出現嘅「+N 項」。
    /// 可以計到負數（行已經比圖標同屯馬綫撐滿）——`layout` 遇負數都照樣留一條。
    static func budget(_ size: Size, train: String? = nil, reserveOverflow: Bool = false) -> CGFloat {
        rowWidth(size) - rowPadding - iconWidth
            - (train.map { badgeWidth($0) } ?? 0)
            - (reserveOverflow ? overflowWidth : 0)
    }

    /// 顯示緊嘅警告 + 收唔落嘅數目（呼叫端寫成「+N 項」）。
    struct Layout {
        var shown: [WeatherWarning]
        var overflow: Int

        static let empty = Layout(shown: [], overflow: 0)
    }

    /// 由嚴重嘅排起（重要警告唔可以比後面嘅擠走，同組保持原本次序），再按估算寬度逐個收；
    /// **至少留一條**：budget 幾細（負數都算）都照顯示第一條，唔可以成行空白；
    /// 收唔落嘅全數計入 `overflow`，所以 `shown.count + overflow == warnings.count`。
    static func layout(_ warnings: [WeatherWarning], limit: Int, width: CGFloat) -> Layout {
        var shown: [WeatherWarning] = []
        var used: CGFloat = 0
        let ordered = warnings.filter { $0.severe } + warnings.filter { !$0.severe }
        if limit > 0 {
            for warning in ordered {
                if shown.count >= limit { break }
                let item = badgeWidth(warning.text)
                if !shown.isEmpty, used + item > width { break }
                used += item
                shown.append(warning)
            }
        }
        return Layout(shown: shown, overflow: warnings.count - shown.count)
    }
}
