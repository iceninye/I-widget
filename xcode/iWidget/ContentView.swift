import SwiftUI
import WidgetKit

/// Widget 嘅宿主 app：「資料」睇 widget 同款資料，「設定」填預覽用 token 同定位授權；
/// 每次開 app 或者低耗電模式變咗，都叫 widget 重新讀取。
struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = AppModel()
    @StateObject private var court = CourtModel()
    @State private var tab = Tab.data

    private enum Tab { case data, court, settings }

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { DataView(model: model) }
                .tabItem { Label("資料", systemImage: "rectangle.grid.2x2.fill") }
                .tag(Tab.data)
            NavigationStack { CourtView(model: court) }
                .tabItem { Label("法院", systemImage: "building.columns.fill") }
                .tag(Tab.court)
            NavigationStack { SettingsView(model: model) { Task { await model.refresh() } } }
                .tabItem { Label("設定", systemImage: "gearshape.fill") }
                .tag(Tab.settings)
        }
        // widget 嘅連結：法院詳情 `iwidget://court?code=…`；更份倒數 `iwidget://duty`（Live Activity 撳入去）
        .onOpenURL { url in
            if url.scheme == "iwidget", url.host == "duty" {
                tab = .data
                Task { await refresh() }
                return
            }
            guard let link = CourtLink(url: url) else { return }
            tab = .court
            court.open(link)
        }
        .task { await refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refresh() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            Task { await refresh() }
        }
    }

    private func refresh() async {
        await model.refresh()
        // 只重讀受影響嘅 kind（今日咭同資訊），唔令無關嘅法院 widget 一齊重讀
        for kind in ["IWidgetOverview", "IWidgetInfo"] {
            WidgetCenter.shared.reloadTimelines(ofKind: kind)
        }
    }
}
