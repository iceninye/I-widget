import SwiftUI

struct SettingsView: View {
    @AppStorage(AppSettings.rosterToken) private var rosterToken = ""
    @AppStorage(AppSettings.vpsToken) private var vpsToken = ""
    @AppStorage(AppSettings.statusURL) private var statusURL = ""
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
        .onChange(of: rosterToken) { _, _ in onChange() }
        .onChange(of: vpsToken) { _, _ in onChange() }
        .onChange(of: statusURL) { _, _ in onChange() }
    }
}
