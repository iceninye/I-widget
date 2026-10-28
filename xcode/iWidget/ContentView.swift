import SwiftUI
import WidgetKit

struct ContentView: View {
    private enum Tab: Hashable { case today, info, courts, settings }

    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = AppModel()
    @State private var tab = Tab.today
    @State private var infoPath: [AppRoute] = []
    @State private var courtPath: [AppRoute] = []
    @State private var courtNavigationID = UUID()

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack {
                DataView(model: model, page: .today)
            }
            .tabItem { Label("今日", systemImage: "calendar") }
            .tag(Tab.today)

            NavigationStack(path: $infoPath) {
                DataView(model: model, page: .info)
                    .navigationDestination(for: AppRoute.self) { route in
                        DataView(model: model, page: route)
                    }
            }
            .tabItem { Label("資訊", systemImage: "square.grid.2x2") }
            .tag(Tab.info)

            NavigationStack(path: $courtPath) {
                CourtDetailView()
                    .navigationDestination(for: AppRoute.self) { route in
                        if case let .court(code, date) = route {
                            CourtDetailView(initialCode: code, initialDate: date)
                        }
                    }
            }
            .id(courtNavigationID)
            .tabItem { Label("法院", systemImage: "building.columns") }
            .tag(Tab.courts)

            NavigationStack { SettingsView { Task { await model.refresh() } } }
                .tabItem { Label("設定", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        .task { await refresh() }
        .onOpenURL(perform: open)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refresh() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            Task { await refresh() }
        }
    }

    private func open(_ url: URL) {
        guard let route = AppRoute(url: url) else { return }
        switch route {
        case .today:
            tab = .today
        case .court(let code, let date):
            courtNavigationID = UUID()
            courtPath = code == nil && date == nil ? [] : [route]
            tab = .courts
        default:
            infoPath = route == .info ? [] : [route]
            tab = .info
        }
    }

    private func refresh() async {
        await model.refresh()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
