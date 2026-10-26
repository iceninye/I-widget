import SwiftUI
import WidgetKit

/// Widget 嘅宿主 app：「資料」睇 widget 同款資料，「設定」填預覽用 token 同定位授權；
/// 每次開 app 或者低耗電模式變咗，都叫 widget 重新讀取。
struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = AppModel()

    var body: some View {
        TabView {
            NavigationStack { DataView(model: model) }
                .tabItem { Label("資料", systemImage: "rectangle.grid.2x2.fill") }
            NavigationStack { SettingsView { Task { await model.refresh() } } }
                .tabItem { Label("設定", systemImage: "gearshape.fill") }
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
