import SwiftUI
import WidgetKit

/// 今日咭、各項資訊（Overview.swift）；之後再加法院。
@main
struct IWidgetBundle: WidgetBundle {
    var body: some Widget {
        IWidget()
        InfoWidget()
    }
}
