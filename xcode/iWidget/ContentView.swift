import SwiftUI
import WidgetKit

/// Widget 嘅宿主 app：顯示 app 內讀到嘅數值，方便對照 widget；
/// 每次開 app 或者低耗電模式變咗，都叫 widget 重新讀取。
struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var stats = SystemStats.read()
    @StateObject private var location = LocationAuth()

    var body: some View {
        NavigationStack {
            List {
                Section("目前讀數（app 內）") {
                    LabeledContent("電量", value: Formatting.percent(stats.batteryLevel))
                    LabeledContent("儲存空間", value: Formatting.storagePair(free: stats.freeBytes, total: stats.totalBytes))
                    LabeledContent(
                        "開機時間",
                        value: Formatting.uptime(stats.uptime(at: Date()))
                            + RebootHint.level(uptime: stats.uptime(at: Date())).suffix
                    )
                    LabeledContent("系統版本", value: stats.versionText)
                    LabeledContent("低耗電模式", value: stats.isLowPowerMode ? "已開啟" : "未開啟")
                }
                Section("天氣定位") {
                    LabeledContent("定位授權", value: location.text)
                    if !location.isAuthorised {
                        Button("允許定位（使用 App 期間）") { location.request() }
                    }
                }
                Section("加入 widget") {
                    Text("長按 Home Screen → 左上角 + → 搜尋「i-widget」→ 揀尺寸。鎖屏：自訂 → 加 widget。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("i-widget")
        }
        .onAppear(perform: refresh)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            refresh()
        }
    }

    private func refresh() {
        stats = SystemStats.read()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
