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
主畫面長按 → 左上角 **+** → 搵 **i-widget**，有三個 widget（各自加、各自設定）：
- **今日咭**（中）：今日更份、返／放工倒數、更份進度、路線時數、明日。長按 →「編輯小工具」填 tml-roster 同步 token；撳內容會打開 app 睇整週更表。學校日程已搬去「各項資訊」。
  舊有大尺寸今日咭要喺主畫面改成中尺寸。
- **各項資訊**（大）：天氣警告、屯馬綫、香港天文台實時天氣、香港 AQHI（中西區一般監測站）、紫外線（京士柏）、學校日程、財經及裝置入口、VPS。每項各自標明來源時間，舊資料會標示。長按 →「編輯小工具」填 VPS token
  （唔使打 `Bearer`）；VPS 網址已預設 `https://n8n.itswong.site/status.json`，留空就得。
- **法院案件表**（大）：司法機構法庭日誌（e-services.judiciary.hk/dcl）全部法院已解析排期，每頁三間；箭嘴可即時翻頁，亦可設定每約十分鐘自動轉頁（實際時間由系統排程）。
  撳法院打開 app「法院」分頁：可揀日期、揀法院或一次過睇全部，搜尋案號，逐個聆訊有詳情頁（複製案號、開原案件表網頁）。唔顯示訴訟各方（網站話明個人資料不可再用）。18:30 後轉睇下一個工作天，並跳過週末及公眾假期。
  只顯示公開網頁中已解析嘅排期；附件或未識別內容可能未列出，並非完整出庭紀錄。

Token 係各個 widget 自己儲存嘅，所以拆咗之後，「各項資訊」要重新填一次 VPS token。

電量剩餘時間係 widget 自己記錄電量變化估算，拔電後大約 40 分鐘先有數。
鎖屏：長按鎖屏 → 自訂 → 加入元件 → 今日咭有行內／長方形，各項資訊有圓形（電量）。

## 常見問題
- **免費 Apple ID 簽名 7 日有效**：過期後 app 開唔到，接機再 Run 一次就得。付費開發者帳號為一年。
- **Widget 搵唔到**：確認 `iWidget` app 已裝並開過一次；重啟 iPhone。
- **改完 `project.yml`**：要重新 `xcodegen generate`。`.xcodeproj` 係產生出嚟嘅，唔使 commit。
- **跑單元測試**：Xcode 揀 scheme iWidget，按 ⌘U；CI（`.github/workflows/ios.yml`）都會自動跑。
