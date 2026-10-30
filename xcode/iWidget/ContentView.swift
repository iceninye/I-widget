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
            NavigationStack { SettingsView { Task { await model.refresh() } } }
                .tabItem { Label("設定", systemImage: "gearshape.fill") }
                .tag(Tab.settings)
        }
        // widget 嘅法院連結：跳去法院分頁，有案號就打開該聆訊嘅詳情
        .onOpenURL { url in
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
        WidgetCenter.shared.reloadAllTimelines()
    }
}
