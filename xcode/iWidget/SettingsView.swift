import SwiftUI

struct SettingsView: View {
    @AppStorage(AppSettings.rosterToken) private var rosterToken = ""
    @AppStorage(AppSettings.vpsToken) private var vpsToken = ""
    @AppStorage(AppSettings.statusURL) private var statusURL = ""
    @AppStorage(HandoverNotifier.enabledKey) private var handoverAlerts = false
    @State private var handoverStatus = ""
    /// 已經觸發過刷新嘅 token 組合：用嚟分辨「用家真係改過嘢」同「啱啱入頁」，
    /// 並喺 debounce 完成之後先更新（取消咗就留舊值，等最新嗰次輸入先發）。
    @State private var firedKey: String?
    @StateObject private var location = LocationAuth()
    @ObservedObject var model: AppModel
    /// 一定要做到嘅刷新（`ContentView` 傳入 `mustRefresh: true`）：跑緊嗰輪要排返隊補跑，
    /// 唔然用家打完最後幾個字會被嗰輪吞咗，成個 token 永遠更新唔到。
    let onChange: () -> Void

    var body: some View {
        Form {
            Section {
                SecureField("tml-roster 同步 token", text: $rosterToken)
                SecureField("VPS token", text: $vpsToken)
                TextField("VPS 網址（留空用預設）", text: $statusURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
            } header: {
                Text("資料預覽用")
            } footer: {
                Text("只用嚟喺 app 預覽。Widget 嘅 token 要喺 widget 長按 →「編輯小工具」另外填：免費簽名冇 App Group，app 同 widget 唔可以共用設定。")
            }
            Section {
                Toggle("交接提示", isOn: $handoverAlerts)
                NavigationLink("提示時間、語音、試聲") { HandoverSettingsView(model: model) }
                if !handoverStatus.isEmpty {
                    Text(handoverStatus).font(.footnote).foregroundStyle(.secondary)
                }
            } header: {
                Text("交接提示")
            } footer: {
                Text("""
                用上面嘅 tml-roster token，排好今日同明日返工前、每次接車、落地嘅通知（預設提前 15 分鐘，返工另加 1 小時前），會講埋接你／交俾邊個更、Run 同之後做咩。
                每次開 app 會重排。唔想日日開 app：捷徑 App →「自動化」→「個人」→ 每日一個時間（例如 03:30）→ 動作「排交接提示」→ 揀「立即執行」。
                通知一響會由手機喇叭讀出成句（開咗靜音掣就只會震）。
                """)
            }
            Section("天氣定位") {
                LabeledContent("定位授權", value: location.text)
                if !location.isAuthorised {
                    Button("允許定位（使用 App 期間）") { location.request() }
                }
            }
            Section("加入 widget") {
                Text("""
                長按主畫面 → 左上角 + → 搜尋「i-widget」：
                • 今日咭（中／大）：填 tml-roster token
                • 各項資訊（大）：填 VPS token
                鎖屏：自訂 → 加入元件。調色風格喺 widget 撳調色掣轉。
                """)
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("設定")
        .task { await refreshHandoverStatus() }
        .onChange(of: handoverAlerts) { _, enabled in
            Task {
                if enabled {
                    if await HandoverNotifier.requestAuthorization() {
                        onChange()
                    } else {
                        handoverAlerts = false
                        handoverStatus = "未允許通知：去 iPhone 設定 →「通知」→ i-widget 開啟。"
                        return
                    }
                } else {
                    await HandoverNotifier.disable()
                }
                // 等重排完先更新狀態
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                await refreshHandoverStatus()
            }
        }
        // 改 token：停手 0.5 秒先打網（寫法同 `HandoverSettingsView` 一樣用 `.task(id:)`，
        // id 一改就會取消上一個未起嘅刷新）。逐個字觸發會一輪接一輪打網，而且跑緊嗰輪讀嘅
        // 係輪開始時嘅舊 token，所以一定要等到最後輸入先發；發出去用 `mustRefresh: true`，
        // 就算嗰時有輪跑緊都會排返隊補跑，最後嗰次輸入必定做到（規則見 `RefreshQueue`）。
        .task(id: tokenKey) {
            switch RefreshQueue.tokenEdit(current: tokenKey, lastFired: firedKey) {
            case .firstSeen:
                // 啱啱入頁：而家嘅值係儲存入面既有嘅，唔算用家改嘢，唔使打網
                firedKey = tokenKey
            case .unchanged:
                break
            case .fire:
                try? await Task.sleep(nanoseconds: RefreshQueue.settingsDebounceNanos)
                // 期間又改咗字：呢個 task 已被取消，交俾最新嗰次輸入去發
                guard !Task.isCancelled else { return }
                firedKey = tokenKey
                onChange()
            }
        }
    }

    /// 三個輸入框合成一個 id：任何一格改過都算「改過」，唔使寫三次 debounce。
    private var tokenKey: String { "\(rosterToken)\u{1}\(vpsToken)\u{1}\(statusURL)" }

    private func refreshHandoverStatus() async {
        guard handoverAlerts else {
            handoverStatus = ""
            return
        }
        let count = await HandoverNotifier.pendingCount()
        guard let next = await HandoverNotifier.next() else {
            handoverStatus = "未有排咗嘅提示（今日同明日冇更份卡，或者未填 token）。"
            return
        }
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "Asia/Hong_Kong")
        formatter.dateFormat = "M/d HH:mm"
        handoverStatus = "已排 \(count) 個。下一個 \(formatter.string(from: next.0))：\(next.1)"
    }
}
