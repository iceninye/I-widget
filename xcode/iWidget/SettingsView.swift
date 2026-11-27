import SwiftUI

struct SettingsView: View {
    @State private var rosterToken = ""
    @State private var vpsToken = ""
    @State private var statusURL = ""
    @State private var secretsReadable = false
    @State private var secretReadError = ""
    @AppStorage(AppSettings.scriptableTheme) private var scriptableTheme = WidgetTheme.classic.rawValue
    @AppStorage(HandoverNotifier.enabledKey) private var handoverAlerts = false
    @State private var handoverStatus = ""
    @State private var secretSaveError = ""
    /// 已經觸發過刷新嘅 token 組合：用嚟分辨「用家真係改過嘢」同「啱啱入頁」，
    /// 並喺 debounce 完成之後先更新（取消咗就留舊值，等最新嗰次輸入先發）。
    @State private var firedKey: String?
    @StateObject private var location = LocationAuth()
    @State private var pickingFolder = false
    @ObservedObject var model: AppModel
    @ObservedObject var bridge: ScriptableBridgeController
    /// 一定要做到嘅刷新（`ContentView` 傳入 `mustRefresh: true`）：跑緊嗰輪要排返隊補跑，
    /// 唔然用家打完最後幾個字會被嗰輪吞咗，成個 token 永遠更新唔到。
    let onChange: () -> Void

    var body: some View {
        Form {
            Section {
                SecureField("tml-roster 同步 token", text: $rosterToken)
                    .disabled(!secretsReadable)
                SecureField("VPS token", text: $vpsToken)
                    .disabled(!secretsReadable)
                TextField("VPS 網址（留空用預設）", text: $statusURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .disabled(!secretsReadable)
                if !secretReadError.isEmpty {
                    Text(secretReadError).font(.footnote).foregroundStyle(.red)
                    Button("重新讀取私密資料") { loadSecrets() }
                }
                if !secretSaveError.isEmpty {
                    Text(secretSaveError).font(.footnote).foregroundStyle(.red)
                    Button("重試儲存私密資料") {
                        if persistSecrets() { onChange() }
                    }.disabled(!secretsReadable)
                }
            } header: {
                Text("私密資料")
            } footer: {
                Text("用嚟 app 內預覽、通知同 Live Activity；Scriptable 只收 app 匯出嘅 JSON，唔會收到 token。原生 Widget 仍然要喺長按 →「編輯小工具」另外填 token。")
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
            Section {
                LabeledContent("狀態", value: bridge.status.message)
                if let at = bridge.status.lastSuccessAt {
                    Text("上次寫入：\(Formatting.clock(at))").font(.footnote).foregroundStyle(.secondary)
                }
                Button(bridge.hasAuthorization ? "更改 Scriptable 資料夾" : "選擇 Scriptable 資料夾") {
                    pickingFolder = true
                }
                if bridge.status.state != .notConfigured, bridge.status.state != .needsReauthorization {
                    Button("立即寫入 JSON") { bridge.writeNow() }
                        .disabled(bridge.status.state == .writing)
                    Button("移除資料夾授權", role: .destructive) { bridge.revokeAuthorization() }
                }
            } header: {
                Text("Scriptable 同步")
            } footer: {
                Text("喺 Files → iCloud Drive 揀 Scriptable 呢個資料夾本身，唔好揀入面嘅子資料夾。app 只寫入 i-widget.json，token 唔會出 app。寫入成功唔代表 iCloud 已同步或 Widget 已刷新。")
            }
            Section {
                Picker("Scriptable 主題", selection: $scriptableTheme) {
                    ForEach(WidgetTheme.allCases, id: \.rawValue) { theme in
                        Text(theme.label).tag(theme.rawValue)
                    }
                }
            } footer: {
                Text("只影響 Scriptable 元件；原生 Widget 調色風格仍然獨立。")
            }
            Section("加入 widget") {
                Text("""
                Scriptable：載入 scriptable/i-widget.js，加入今日咭、各項資訊、法院、時鐘或鎖屏元件。喺元件參數揀 view；主題喺上面「Scriptable 主題」揀。

                原生 Widget（並行驗證保留）：長按主畫面 → 左上角 + → 搜尋「i-widget」：
                • 今日咭（中／大）：填 tml-roster token
                • 各項資訊（大）：填 VPS token
                鎖屏：自訂 → 加入元件。調色風格喺 widget 撳調色掣轉。
                """)
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("設定")
        .sheet(isPresented: $pickingFolder) {
            FolderPicker(onPick: { folder in
                bridge.authorize(folder: folder)
                if bridge.hasAuthorization { onChange() }
                pickingFolder = false
            }, onCancel: {
                pickingFolder = false
            })
        }
        .task {
            loadSecrets()
            await refreshHandoverStatus()
        }
        .onChange(of: scriptableTheme) { _, _ in onChange() }
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
                guard secretSaveError.isEmpty else { return }
                try? await Task.sleep(nanoseconds: RefreshQueue.settingsDebounceNanos)
                // 期間又改咗字：呢個 task 已被取消，交俾最新嗰次輸入去發
                guard !Task.isCancelled else { return }
                firedKey = tokenKey
                // 停手後先寫 Keychain；成功先通知刷新，唔好網絡同 UI 已用新值但儲存其實失敗。
                if persistSecrets() { onChange() }
            }
        }
    }

    @MainActor
    private func loadSecrets() {
        do {
            let roster = try AppSettings.secretString(AppSettings.rosterToken)
            let vps = try AppSettings.secretString(AppSettings.vpsToken)
            let url = try AppSettings.secretString(AppSettings.statusURL)
            rosterToken = roster ?? ""
            vpsToken = vps ?? ""
            statusURL = url ?? ""
            secretsReadable = true
            secretReadError = ""
            secretSaveError = ""
            // 讀取完成後先同步 baseline，避免非同步載入被誤判成用戶編輯而打網／重寫。
            firedKey = tokenKey
        } catch {
            // 讀取失敗唔可以當成空值：保持欄位停用，亦阻止 debounce／重試按鈕盲寫三個值。
            secretsReadable = false
            secretReadError = "無法讀取私密資料，已停止編輯以避免覆蓋現有 token。請重試。"
        }
    }

    @MainActor
    private func persistSecrets() -> Bool {
        guard secretsReadable else {
            secretSaveError = "私密資料尚未成功讀取，不能儲存。請先重新讀取。"
            return false
        }
        let saved = AppSettings.saveSecrets(rosterToken: rosterToken, vpsToken: vpsToken, statusURL: statusURL)
        secretSaveError = saved ? "" : "私密資料儲存失敗，可能仍在使用舊 token。請重試。"
        return saved
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
