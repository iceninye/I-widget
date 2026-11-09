import SwiftUI

struct SettingsView: View {
    @AppStorage(AppSettings.rosterToken) private var rosterToken = ""
    @AppStorage(AppSettings.vpsToken) private var vpsToken = ""
    @AppStorage(AppSettings.statusURL) private var statusURL = ""
    @AppStorage(HandoverNotifier.enabledKey) private var handoverAlerts = false
    @State private var handoverStatus = ""
    @StateObject private var location = LocationAuth()
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
                if !handoverStatus.isEmpty {
                    Text(handoverStatus).font(.footnote).foregroundStyle(.secondary)
                }
            } header: {
                Text("交接提示")
            } footer: {
                Text("""
                用上面嘅 tml-roster token，排好今日同明日每次落地（前 5 分鐘）、接車（前 5 分鐘；用膳後第一程前 15 分鐘）嘅通知，會講埋接你／交俾邊個更同 Run。
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
        .onChange(of: rosterToken) { _, _ in onChange() }
        .onChange(of: vpsToken) { _, _ in onChange() }
        .onChange(of: statusURL) { _, _ in onChange() }
    }

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
