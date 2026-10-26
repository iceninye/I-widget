import SwiftUI
import WidgetKit

/// 今日咭、各項資訊（Overview.swift）；同法院案件表（CourtWidget.swift）。
@main
struct IWidgetBundle: WidgetBundle {
    var body: some Widget {
        IWidget()
        InfoWidget()
        CourtWidget()
    }
}
