import SwiftUI
import WidgetKit

/// Widget 嘅宿主 app：「資料」睇 widget 同款資料，「設定」填預覽用 token 同定位授權；
/// 每次開 app 或者低耗電模式變咗，都叫 widget 重新讀取。
/// 刷新全部經 `requestRefresh()` 串行化：冷啟、deep link、返前景、電量改變、改設定唔會同時打幾輪網。
/// 「一定要做到」嘅請求（deep link、返前景、跨過事件邊界）會排隊補跑一次，唔會俾 loading guard 吞咗
/// （見 `pendingRefresh`）；純順手刷新（冷啟、低耗電、改設定打字）就併入跑緊嗰輪。
struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = AppModel()
    @StateObject private var court = CourtModel()
    @State private var tab = Tab.data

    private enum Tab { case data, court, settings }

    /// 前景心跳間隔：tick 本身唔打網，淨係睇有冇跨過更份事件邊界（跨過咗先 refresh）。
    private static let tickInterval: TimeInterval = 60

    /// 未跨過嘅事件邊界（事件時間 + 1 秒，最多 8 個），取法同 `Overview` widget timeline 一致。
    @State private var boundaries: [Date] = []
    /// 有冇一個刷新循環跑緊：令冷啟／deep link／返前景唔會同時打幾輪。
    @State private var refreshing = false
    /// 跑緊嗰時又到嘅新請求：記低佢，等前一輪完咗補跑一次。
    /// 呢個先係「deep link 嗰次更新一定做到」嘅保證——如果淨係靠 `AppModel` 嘅 loading guard，
    /// 由 Live Activity 撳入嚟嗰次會俾前一輪默默吞咗，鎖定畫面睇落仍然係舊內容。
    @State private var pendingRefresh = false
    /// 只有真係落過背景再返嚟先再拉一次；冷啟嗰輪已經由 `.task` 負責，
    /// 唔使 task + scenePhase + deep link 三次重複冷啟 refresh。
    @State private var wentToBackground = false

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { DataView(model: model) { requestRefresh(mustRefresh: true) } }
                .tabItem { Label("資料", systemImage: "rectangle.grid.2x2.fill") }
                .tag(Tab.data)
            NavigationStack { CourtView(model: court) }
                .tabItem { Label("法院", systemImage: "building.columns.fill") }
                .tag(Tab.court)
            NavigationStack { SettingsView(model: model) { requestRefresh() } }
                .tabItem { Label("設定", systemImage: "gearshape.fill") }
                .tag(Tab.settings)
        }
        // widget 嘅連結：法院詳情 `iwidget://court?code=…`；更份倒數 `iwidget://duty`（Live Activity 撳入去）
        .onOpenURL { url in
            if url.scheme == "iwidget", url.host == "duty" {
                tab = .data
                // 如果冷啟本身係由 deep link 開進 app，`.task` 嗰輪可能正喺度跑：排佢返隊，完咗補跑一次，
                // 呢次更新一定做到；而 `AppModel.rescheduleHandover` 會順手更新 Live Activity 內容。
                requestRefresh(mustRefresh: true)
                return
            }
            guard let link = CourtLink(url: url) else { return }
            tab = .court
            court.open(link)
        }
        .task {
            await refreshQueued()   // 冷啟：拉一次（之後每次跨過事件邊界先再拉）
            await tickLoop()        // 前景心跳：每 60 秒檢查邊界，冇跨過就唔打網
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                wentToBackground = true
            case .inactive:
                break   // 落通知遮罩、app switcher 唔算離開，唔使多打一次網
            case .active:
                // 冷啟嗰次已經由 `.task` 計，所以要等真係落過背景先算「返嚟」
                if wentToBackground {
                    wentToBackground = false
                    requestRefresh(mustRefresh: true)
                } else {
                    // 由通知遮罩／app switcher 返嚟：可能已經跨過事件，但唔使重新下載。
                    tick(now: Date())
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            requestRefresh()
        }
    }

    /// 所有觸發位嘅統一入口：本身唔做嘢，只係將請求排返去 main actor（`onOpenURL`、Button、
    /// `onReceive` 呢啲 closure 係 nonisolated，唔可以直接調用 `@MainActor` 隔離嘅實作）。
    /// - Parameter mustRefresh: `true` = 呢次一定要做到（排隊補跑）；`false` = 得喺冇人跑嗰時先跑。
    private func requestRefresh(mustRefresh: Bool = false) {
        Task { @MainActor in await self.refreshQueued(mustRefresh: mustRefresh) }
    }

    /// 串行化刷新：已經有一輪跑緊就只記低「又要跑一次」，等佢完咗補跑；冇人跑就即刻開一輪。
    /// - `mustRefresh: true`（deep link、返前景、跨過事件邊界）：跑緊嗰輪唔可以吞咗呢次，要排隊補跑，
    ///   即每次呢類觸發最終都做得到一次（最多前後兩輪，唔會循環）。
    /// - `mustRefresh: false`（冷啟、低耗電模式改變、改設定輸入框）：有輪跑緊就當佢已經包底，唔使重複打網。
    ///   設定頁逐個字都會觸發呢度，如果每次都補跑就會一輪接一輪；冷啟由 deep link 開入嚟嗰次已經係
    ///   `mustRefresh`，所以「deep link 一定要更新一次」係靠上面嗰條，唔靠冷啟呢條。
    @MainActor
    private func refreshQueued(mustRefresh: Bool = false) async {
        if refreshing {
            if mustRefresh { pendingRefresh = true }
            return
        }
        refreshing = true
        repeat {
            pendingRefresh = false
            if await model.refresh() {
                reloadWidgets()
                // 啱啱攞到新更表：即刻照新資料排好事件邊界，唔使再等多一個 tick
                boundaries = Self.eventBoundaries(from: model.entry, now: Date())
            }
        } while pendingRefresh
        refreshing = false
    }

    /// 只重讀受影響嘅 kind（今日咭同資訊），唔令無關嘅法院 widget 一齊重讀。
    @MainActor
    private func reloadWidgets() {
        for kind in ["IWidgetOverview", "IWidgetInfo"] {
            WidgetCenter.shared.reloadTimelines(ofKind: kind)
        }
    }

    /// 前景心跳：每 60 秒 tick 一次。app 落背景會被凍結、view 消失時 `.task` 亦會取消，
    /// 所以背景一般唔會繼續計；`tick` 入面再核一次 `scenePhase`，唔假設凍結一定準時。
    @MainActor
    private func tickLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: UInt64(Self.tickInterval * 1_000_000_000))
            if Task.isCancelled { break }
            tick(now: Date())
        }
    }

    /// 只喺「資料」分頁 + 前景先監視；其他情況清掉名單（返嚟重新排，唔會用住舊事件）。
    /// 跨過咗邊界（例如 05:20 返工嗰一刻，「下一件事」同倒數要變）先 refresh 一次，冇跨過就唔打網。
    /// 名單每個 tick 都照最新 `model.entry` 重新排，所以換日、改更表都跟得到；
    /// 只有名單真係變咗先寫 `@State`，唔會造成無窮 View 更新。
    @MainActor
    private func tick(now: Date) {
        guard tab == .data, scenePhase == .active else {
            if !boundaries.isEmpty { boundaries = [] }
            return
        }
        let crossed = boundaries.first.map { now >= $0 } ?? false
        let next = Self.eventBoundaries(from: model.entry, now: now)
        if next != boundaries { boundaries = next }
        if crossed { requestRefresh(mustRefresh: true) }
    }

    /// 更份事件（返工、接車、落地、放工）嗰一刻 + 1 秒，最多 8 個——取法同 widget timeline 一致，
    /// 一律經 `DutyActivityPlan.boundaries`，唔喺呢度重寫一次規則。
    /// 另外加 04:00 服務日轉日：最後一件事之後冇事件邊界，但「今日」已經係另一日，都要醒一次。
    private static func eventBoundaries(from entry: OverviewEntry, now: Date) -> [Date] {
        var dates = DutyActivityPlan.boundaries(events: entry.schedule.dutyEvents(now: now), now: now)
        if let flip = ICalendar.hongKong.nextDate(
            after: now, matching: DateComponents(hour: 4, minute: 0), matchingPolicy: .nextTime
        ), flip < now.addingTimeInterval(24 * 3_600) {
            dates.append(flip.addingTimeInterval(1))
        }
        return dates.sorted()
    }
}
