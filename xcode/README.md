# i-widget 原生 Xcode 專案：安裝到 iPhone

需要：Mac、Xcode 15 或以上、iPhone（iOS 17+）、USB 線、Apple ID（免費即可）。

## 1. 產生專案
```sh
brew install xcodegen
git clone https://github.com/iceninye/I-widget.git
cd I-widget/xcode
xcodegen generate
open iWidget.xcodeproj
```
（要用 PR 分支就先 `git checkout <分支名>`。）

## 2. 簽名
1. 左邊揀專案 **iWidget** → 逐個 target（`iWidget`、`iWidgetExtension`）→ **Signing & Capabilities**。
2. 兩個 target 都揀同一個 **Team**（你嘅 Apple ID；未登入就去 Xcode → Settings → Accounts 加）。
3. Bundle id 係 `com.iceninye.i-widget`（Extension：`com.iceninye.i-widget.widget`）。如果再被佔用，就改做自己獨有嘅（例如加你個名），
   Extension 要保持以 app id 開頭（`.widget` 結尾）。改喺 `project.yml` 再 `xcodegen generate` 最穩陣。
   亦可以喺 `project.yml` 填 `DEVELOPMENT_TEAM` 嘅 Team ID，重新產生專案後就唔使逐個揀。

## 3. 安裝
1. iPhone 用線接 Mac，解鎖並㩒「信任此電腦」。
2. iPhone：設定 → 隱私權與安全性 → **開發者模式** → 開啟，然後重新啟動。
3. Xcode 上方 scheme 揀 **iWidget**，裝置揀你部 iPhone，㩒 **Run (⌘R)**。
4. 第一次會提示「不受信任嘅開發者」：設定 → 一般 → **VPN 與裝置管理** → 揀你個 Apple ID → 信任。再 Run 一次。

## 4. 加 widget
主畫面長按 → 左上角 **+** → 搵 **i-widget**，有兩個 widget（各自加、各自設定）：
- **今日咭**（中／大）：今日更份、未來 7 日、本週概況、明日、學校日程。長按 →「編輯小工具」填 tml-roster 同步 token。
- **各項資訊**（大）：天氣警告、屯馬綫、電量、儲存、開機、天氣、黃金、系統版本、VPS。長按 →「編輯小工具」填 VPS token
  （唔使打 `Bearer`）；VPS 網址已預設 `https://n8n.itswong.site/status.json`，留空就得。

Token 係各個 widget 自己儲存嘅，所以拆咗之後，「各項資訊」要重新填一次 VPS token。

電量剩餘時間係 widget 自己記錄電量變化估算，拔電後大約 40 分鐘先有數。
鎖屏：長按鎖屏 → 自訂 → 加入元件 → 今日咭有行內／長方形，各項資訊有圓形（電量）。

## 常見問題
- **免費 Apple ID 簽名 7 日有效**：過期後 app 開唔到，接機再 Run 一次就得。付費開發者帳號為一年。
- **Widget 搵唔到**：確認 `iWidget` app 已裝並開過一次；重啟 iPhone。
- **改完 `project.yml`**：要重新 `xcodegen generate`。`.xcodeproj` 係產生出嚟嘅，唔使 commit。
- **跑單元測試**：Xcode 揀 scheme iWidget，按 ⌘U；CI（`.github/workflows/ios.yml`）都會自動跑。
