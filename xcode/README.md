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
- **今日咭**（中／大）：今日更份（頭行有服務日日期）、天氣預報（而家溫度、天氣、高低溫、降雨機會，加返工／放工嗰個鐘嘅逐小時預報）、
  有天氣警告或者屯馬綫唔正常先出現嘅警示行、未來 7 日（每日更份 + 天氣）、本週概況、明日、學校日程。長按 →「編輯小工具」填 tml-roster 同步 token。
  天氣用 Open-Meteo（免 key），同「各項資訊」共用 10 分鐘快取。
- **各項資訊**（大）：天氣警告、屯馬綫、電量、儲存、開機、天氣、黃金、系統版本、紫外線、空氣、匯率、記憶體（一刻快照）、降雨機會、低耗電模式、VPS。位唔夠會由最底一行開始收起。長按 →「編輯小工具」填 VPS token
  （唔使打 `Bearer`）；VPS 網址已預設 `https://n8n.itswong.site/status.json`，留空就得。
- **法院案件表**（大）：司法機構法庭日誌（e-services.judiciary.hk/dcl），長按 →「編輯小工具」揀最多 4 個法院。
  每個法院先列全日分類統計（刑事、民事、家事、上訴、審裁處、死因），再逐個聆訊兩行顯示：時間、案號、法庭；
  類別（行頭色條同標籤）、案件類型（按案號前綴推斷，例如 DCCJ = 民事訴訟、KCCC = 刑事案件）· 聆訊性質（答辯、訊問、審訊…）、法官。
  聆訊性質只認固定字眼，唔會誤把被告姓名或者控罪當成性質。
  撳法院標題或者任何一行會打開 app「法院」分頁：撳行直接開聆訊詳情，撳標題跳去該法院。唔顯示訴訟各方（網站話明個人資料不可再用）。18:30 後轉睇下一個工作天。
  App 內「法院」分頁可以揀法院、按類別篩選、搜尋案號／法庭／法官／類型，每個聆訊有詳情頁（案件類型、聆訊性質、複製案號、開原案件表網頁）。

Token 係各個 widget 自己儲存嘅，所以拆咗之後，「各項資訊」要重新填一次 VPS token。

電量剩餘時間係 widget 自己記錄電量變化估算，拔電後大約 40 分鐘先有數。
鎖屏：長按鎖屏 → 自訂 → 加入元件 → 今日咭有行內／長方形，各項資訊有圓形（電量）。

## 5. 交接提示（通知＋讀出）
App「設定」填 tml-roster token，再開「交接提示」，允許通知。之後會排好今日同明日嘅通知，每個都講埋之後做咩：
- 上班前（預設 1 小時前同 15 分鐘前）：「1 小時後返工，05:20 喺八鄉廠，111 更」
- 接車前：「15 分鐘後你要喺錦上路 2接 128 更嘅 Run 18，開去烏溪沙」（要泊車會講「之後泊車」）
- 落地前：「15 分鐘後喺錦上路 2落地，接你嗰位係 118 更，之後用膳到 11:16」（之後可以係用膳、泊車、接另一架車、搭車、收工）
- 放工前最後一次落地會講「最後一程」；放工前提示預設唔開

「設定」→「提示時間、語音、試聲」可以改：每種情況提前幾耐（上班兩次、接車、落地、用膳完結、最後一次落地、放工；揀「唔提」就關），
語音（開關、聲線、語速、讀兩次），「試聽」同「5 秒後發測試通知」，同埋睇到將會響嘅全部提示。

接你／交俾邊個更由 TML-traffic 更份卡嘅行程（legs）計，規則同 tml-roster 一樣（同一 Run、同一站、20 分鐘內）。
每次開 app 會重排；唔想日日開 app，用捷徑自動化：捷徑 App →「自動化」→「個人自動化」→「時間」每日（例如 03:30）→
動作搵 i-widget「排交接提示」→ 揀「立即執行」。呢個動作喺背景執行，唔會打開 app。
提示聲係排程時用 iPhone 語音合成（廣東話）錄好嘅句子，通知一響就由手機喇叭讀出，唔使耳機。
語音檔存喺 app 嘅 `Library/Sounds/handover-*.caf`，每次重排都會刪走已經響完或者內容改咗嘅，關咗交接提示就全部刪晒。

冇聲：通知提示聲同其他通知一樣，開咗靜音掣、專注模式，或者鈴聲音量太細都聽唔到。「試聽」唔受靜音掣影響，
試聽有聲而測試通知冇聲，就係靜音掣／專注模式／iPhone 設定 →「通知」→ i-widget →「聲音」嘅問題。
免費簽名冇 Time Sensitive，專注模式會擋住通知，要將 i-widget 加入專注模式嘅允許名單。

## 常見問題
- **免費 Apple ID 簽名 7 日有效**：過期後 app 開唔到，接機再 Run 一次就得。付費開發者帳號為一年。
- **Widget 搵唔到**：確認 `iWidget` app 已裝並開過一次；重啟 iPhone。
- **改完 `project.yml`**：要重新 `xcodegen generate`。`.xcodeproj` 係產生出嚟嘅，唔使 commit。
- **跑單元測試**：Xcode 揀 scheme iWidget，按 ⌘U；CI（`.github/workflows/ios.yml`）都會自動跑。
