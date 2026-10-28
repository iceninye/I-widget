import SwiftUI

struct SettingsView: View {
    @AppStorage(AppSettings.rosterToken) private var rosterToken = ""
    @AppStorage(AppSettings.vpsToken) private var vpsToken = ""
    @AppStorage(AppSettings.statusURL) private var statusURL = ""
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
                Text("更表及 VPS 詳情")
            } footer: {
                Text("目前 App 同 Widget 設定分開儲存。要睇更表及 VPS 詳情，請在此填入 token；Widget 嘅 token 仍然喺「編輯小工具」填。Token 唔會放入跳轉連結。")
            }
            Section("官方觀測資料") {
                Text("天氣、風力、氣壓及 AQHI 按官方測站顯示，詳情列明測站名稱及資料時間，唔代表所在位置嘅即時讀數。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("加入 widget") {
                Text("""
                長按主畫面 → 左上角 + → 搜尋「i-widget」：
                • 今日咭（中）：填 tml-roster token，撳內容睇更表詳情
                • 各項資訊（大）：天氣、AQHI、學校及分類詳情
                • 法院案件表（大）：翻頁瀏覽各院，撳入搜尋已解析排期
                原有大尺寸今日咭需要在主畫面改成中尺寸。
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
