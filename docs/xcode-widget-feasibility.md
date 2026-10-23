# Xcode 原生 widget：功能可行性同設計

首選方案係 `xcode/`（Swift／SwiftUI／WidgetKit）。呢份文件回答三件事：點樣裝上部機（AltStore／TestFlight／App Store Connect）、
Ice 想要嘅每個資訊項目喺 iOS 沙盒下做唔做得到、同埋建議嘅資料來源同更新方式。

## 依據標記（同 `widget-comparison.md` 一致）

- **【程式碼】** repo 現有 Xcode 碼已經做咗（`xcode/Shared/SystemStats.swift` 等）。
- **【知識】** 按 Apple 文件／一般行為，**寫呢份文件時冇辦法上網核對**（agent 環境封咗外部 API），
  所有 API 網址、免費額度、限額都要 Ice 或實作時再核對一次，唔好當成已驗證。
- **【真機待測】** 一定要上真機先知。
- repo 同真機都**未驗證過 Xcode 版**，下面冇任何實測數字。

---

## A. 點樣裝上部 iPhone

### A1. Xcode 直接安裝（而家 README 嘅做法）
Mac ＋ Xcode ＋免費 Apple ID。簽名 **7 日過期**，要接機再 Run。【知識】

### A2. AltStore（sideload，唔使付費帳號）
- AltStore 係喺 iPhone 上嘅 app，用你自己嘅 Apple ID 幫 `.ipa` 重新簽名安裝。電腦要長開 **AltServer**（Mac／Windows），
  同 iPhone 喺同一個 Wi-Fi，AltStore 會喺 7 日到期前自動背景重簽（要電腦開住＋同網絡，錯過就要手動接機刷新）。【知識】
- 免費帳號限制：同時最多 **3 個** sideload app，每週新 App ID 數量有上限。**widget extension 亦計入**，
  所以 app ＋ extension 會食額度。【知識】
- 需要一個 `.ipa`：AltStore 只負責簽名安裝，**唔負責編譯**。兩條路：
  1. 用 Mac Xcode Archive 匯出；
  2. 冇 Mac：用 GitHub Actions macOS runner 編出未簽名 `.ipa`（repo 已有 macOS CI，可擴充），下載後交俾 AltStore 簽名。
     呢條係「冇 Mac 長期用 Xcode 版」嘅可行路線，但 **App Group／Keychain 共用等 entitlement 重簽後會唔會保留，要真機測**。【真機待測】
- 好處：免費、可用 widget。壞處：7 日續簽靠電腦、free 帳號 3 app 限制、Apple 政策改動風險。
- 歐盟用戶有 AltStore PAL（官方替代市集，年費），**香港冇呢個選項**。【知識】

### A3. TestFlight：**要付費**
TestFlight 要加入 **Apple Developer Program（US$99／年）**，免費 Apple ID 用唔到。
Build 90 日過期，需重新上傳。內部測試（最多 100 位 App Store Connect 用戶）唔使審核；外部測試要 Beta 審核。
Ice 自己一個人用，內部測試已足夠。【知識，費用請以 Apple 現行為準】

### A4. App Store Connect
App Store Connect 係付費開發者帳號嘅網站後台：上傳 build、管理 TestFlight、填上架資料同提交審核。
冇付費帳號就入唔到。上架公開 App Store 要審核同符合指引，對「個人用 widget」唔必要；
個人長期用，**TestFlight 內部測試**最輕鬆。若只想自己裝又唔想 90 日重傳，可以睇 Ad Hoc（登記最多 100 部裝置、簽名一年）。【知識】

### 揀法
| 情況 | 建議 |
| --- | --- |
| 有 Mac、唔想付錢 | A1，每 7 日 Run 一次 |
| 唔想每 7 日手動 | A2（電腦要開）或付費＋A3 |
| 想最省事、最穩 | 付費帳號 ＋ TestFlight（內部）|
| 冇 Mac | A2 ＋ CI 出 `.ipa`（要先試）|

付費帳號仲會解鎖：Push 更新 widget（見 B 節）、WeatherKit、iCloud 等。部分功能（如 WeatherKit、Push）**免費帳號做唔到**。【知識】

---

## B. 更新機制（誠實版：冇真正 real time）

WidgetKit 嘅事實：
- widget 唔係常駐 process。系統叫 extension 行 `getTimeline`，之後只按 timeline entry 渲染。
- `Timeline` 嘅 `.after(date)`／`.atEnd` 只係「唔早於」，系統按**每日預算**（常見講法每個 widget 約 40–70 次／日，會按使用習慣變）決定幾時真正 reload。低耗電模式同冇用 app 嘅 widget 會更少。【知識】
- 時鐘類（開機時間、倒數）**唔使 reload**：預先生成多個 entry，或用 `Text(date, style: .timer/.relative)` 交俾系統跳。repo 已經咁做。【程式碼】

按服務揀方法：

| 資料 | 變化速度 | 建議更新方式 |
| --- | --- | --- |
| 開機時間、今日進度 | 每分鐘 | 預生成 entry／系統計時 Text，唔使網絡 |
| 電量、充電、儲存、RAM | 慢～中 | 每次 timeline reload 順手讀（約 15–30 分鐘）|
| 天氣 | 慢 | `.after` 30–60 分鐘；網絡喺 `getTimeline` 內直接 fetch，失敗用上次快取 |
| 日曆（今日／明日）| 事件界線 | 每個 entry 按「下一個事件開始／結束」時間切換，唔使 reload；每 30 分鐘或 `EKEventStoreChanged` 由 app 觸發 reload |
| 黃金價格 | 秒級 | **做唔到真 real time**。每 15–30 分鐘 reload，顯示「更新於 HH:mm」；要更密只可靠 app 開住時 `WidgetCenter.reloadAllTimelines()` |
| VPS 狀態 | 慢 | 每 1–6 小時；伺服器自己每小時產生一次狀態 JSON |
| iOS 最新版本 | 好慢 | 每日 1 次，快取 |

其他手段：
- **主 app 背景刷新**（`BGAppRefreshTask`）：由系統安排，唔保證，可用嚟喺 app 寫快取到 App Group，再 reload widget。【知識】
- **Push 更新 widget**（`WidgetPushHandler`，iOS 26 起）：伺服器經 APNs 叫 widget reload，最接近 real time，
  但要**付費帳號＋自己嘅推送伺服器**，對個人黃金價格嚟講過重。【知識】
- 互動 widget（App Intents）：可以做「撳一下更新」按鈕，一撳就 reload。可行、成本低。【知識】

網絡請求喺 extension 內做，要留意：extension 有時間同記憶體上限，API 要快、payload 要細；失敗必須 fallback 快取。

---

## C. 外觀：Liquid Glass／Clear

- Liquid Glass 由 iOS 26 引入，主畫面 widget 有 **透明（Clear）／Tinted** 外觀，由用戶喺系統揀，**app 控制唔到整體玻璃效果，只可以配合**。【知識】
- 配合做法：
  1. 用 `containerBackground(for: .widget)`，唔好自己畫不透明底；背景用 `.fill.tertiary` 之類半透明或乾脆留空。
  2. 讀 `@Environment(\.widgetRenderingMode)`（`.fullColor`／`.accented`／`.vibrant`）：重點字用 `.widgetAccentable()`，其餘用階層式 `.primary/.secondary`，
     避免硬編碼顏色（Tinted 同 Clear 下會被洗走）。
  3. 圖片／圖示用 `widgetAccentedRenderingMode`；SF Symbols 用 `.symbolRenderingMode(.hierarchical)`。
  4. 增加字重同對比：Clear 下文字壓喺桌布上，字細或太淡會睇唔清。
  5. 進度條／Gauge 避免依賴顏色表達狀態，加圖示或文字（例如「建議重啟」）。
- 現有碼 `Components.swift`、`WidgetViews.swift` 要逐個檢查有冇硬編碼顏色或不透明底。**實際效果一定要真機試 Clear／Tinted／Light／Dark 四種**。【真機待測】
- 我哋對 iOS 27 嘅新 API 冇可靠資料，實作時以 Xcode 當時 SDK 文件為準。

---

## D. 逐項可行性

| # | 項目 | 可行？ | 做法／限制 | 建議資料來源 |
| --- | --- | --- | --- | --- |
| 1 | 今日天氣＋明日預報 | ✅ | 要網絡。位置可固定城市（最簡單）或 CoreLocation（要授權，widget 內有額外限制） | **香港天文台開放數據**（`data.weather.gov.hk` 九天預報／本港地區天氣報告，免費免 key）；通用備選 **Open-Meteo**（免費免 key，非商業）；WeatherKit 最順手但要付費帳號【知識，免費額度待核】|
| 2 | RAM 用量 | ⚠️ 勉強 | 沙盒下冇「其他 app 用咗幾多」。`ProcessInfo.physicalMemory` 讀總量；`host_statistics64` 一般讀到系統層 free/active/inactive/wired 頁數。但 iOS 會積極用 cache／壓縮，數字同開發者直覺唔同，而且**只係 extension 運行嗰刻嘅快照**，唔代表你睇 widget 時 | 系統 API，冇外部來源。建議標「約」，或用「可用記憶體」而唔係「用量 %」；價值低，列低優先【知識，真機待測】|
| 3 | 儲存空間 | ✅ | 已完成，同設定一致 | `volumeAvailableCapacityForImportantUsage`【程式碼】|
| 4 | 開機時間（7 日提示）| ✅ | 已有 `kern.boottime`；加規則：≥7 日顯示「建議重啟」並轉警示色；5–7 日轉黃。注意「開機」唔等於「用戶關機」，只係上次重啟 | 系統 API【程式碼】|
| 5 | 現時 iOS 版本 | ✅ | `UIDevice.systemVersion` 已有 | 系統 API【程式碼】|
| 5b | 最新 iOS 版本 | ⚠️ 有網絡 | Apple 冇正式、有保障嘅公開 API。選項：endoflife.date（有 iOS 產品 JSON，穩定、簡單）、Apple 嘅 `gdmf.apple.com/v2/pmv`（MDM 用，未文件化，可能變）。注意要分「最新大版本」同「呢個大版本最新小版本」；有 beta 需要過濾 | **endoflife.date** 為主【知識，未能核對】|
| 6 | 預計電池剩餘時間 | ❌ 直接做唔到 | iOS **冇任何公開 API** 提供剩餘時間或放電電流。Widget 亦唔可以持續取樣。**替代**：每次 reload 將（時間，電量）寫入 App Group，用最近數個放電樣本線性外推「約可用 X 小時」；充電中則推算充滿時間。樣本間隔 15–30 分鐘、受系統延遲影響，精度粗，要標「估算」，樣本太少（<2 個）就顯示「—」 | 自己累積嘅數據；亦可顯示「電量＋低耗電模式」作誠實後備 |
| 7 | 今日工作更份＋學校 Google 日曆 | ✅（視乎來源）| 見下面 E 節 | **EventKit**（最佳）／Google Calendar API／iCal 私人網址 |
| 8 | 明日活動概要 | ✅ | 同上，查明日 00:00–24:00 事件，顯示數量＋首兩項 | 同上 |
| 9 | VPS 版本／需否更新 | ✅（要伺服器配合）| widget 內**唔建議 SSH**（要放私鑰／密碼喺手機，又冇成熟 SSH 庫）。見 F 節：伺服器出一個只讀狀態 JSON | 自家狀態 endpoint；或 Uptime Kuma／Netdata／Beszel 嘅 API |
| 10 | 黃金即時價格 | ⚠️ 準即時 | 見 G 節：免費源多數延遲或有額度；widget 本身最快都係 ~15 分鐘一次 | gold-api.com、GoldAPI.io、metals.dev 等【知識，額度待核】|

### 我建議加嘅項目
- 低耗電模式／充電狀態（已有）。
- 日出日落、紫外線、空氣質素（HK 可用 EPD AQHI／天文台 UV 數據）；暴雨／颱風信號（天文台警告 API）。
- 港元匯率（USD/HKD、JPY 等）、同黃金一齊顯示。
- 下一班巴士／港鐵預計時間（KMB／港鐵開放數據），上班通勤用最實用。
- 步數（HealthKit，要授權；free 帳號是否可用要試）。
- Wi-Fi 名稱／VPN 狀態：要定位權限＋entitlement，唔建議。
- 鎖屏 widget 版本：開機時間、電量、下一個事件。

---

## E. 日曆來源（工作更份＋學校 Google 日曆）

**建議首選：EventKit（零憑證）**
喺 iPhone「設定 → 日曆 → 帳號」加入 Google 帳號（學校＋個人），widget／app 用 `EKEventStore` 讀。
- 好處：**唔使喺 app 或 repo 放任何 Google 憑證**；唔使 OAuth；離線有效；日曆更新會觸發 `EKEventStoreChanged`。
- 要求：app 需要 `NSCalendarsFullAccessUsageDescription`（iOS 17+ 授權模式），用戶授權一次。
- 風險：學校 Google Workspace 管理員可能限制第三方裝置同步（若限制，設定入唔到帳號）。
- 可以按日曆名篩選「工作」「學校」兩組，分顏色。

備選：
1. **Google Calendar API＋OAuth**：要 Google Cloud 專案、OAuth client、refresh token；學校 Workspace 可能禁止外部 app 授權；憑證要放 Keychain，成本最高，唔建議。
2. **iCal 私人網址**（日曆設定入面嘅「iCal 格式私人地址」）：簡單、只讀，但**網址本身等同密碼**，只可放 Keychain／App Group，**絕不寫入 repo**；學校可能關閉呢功能。

**「工作更份」**：未知放喺邊。若係日曆事件（例如「早更／夜更」）EventKit 直接讀；若係公司 App／PDF／Excel 就要另想（例如定一個「更份」日曆自己更新）。**要問 Ice。**

---

## F. VPS 狀態設計

widget 只讀，唔入伺服器：

1. VPS 上用 cron／systemd timer 每小時行一個細 script，輸出 JSON，例如：
   `{"os":"Ubuntu 24.04","kernel":"6.8.0-xx","upgradable":12,"security":3,"reboot_required":true,"updated_at":"…"}`
   （資料來自 `/etc/os-release`、`apt list --upgradable`、`/var/run/reboot-required`，RHEL 系用 `dnf check-update`）。
2. 用 nginx／caddy 提供 HTTPS，要 **Bearer token** 或 mTLS；token 只放喺 iPhone Keychain／App Group，由用戶喺 app 設定頁輸入。
3. Widget 每 1–6 小時 fetch，顯示：OS 版本、可更新數、有冇安全更新、需否重啟，狀態色（綠／黃／紅），失敗顯示「離線」＋最後成功時間。
4. 安全原則：endpoint 只讀、唔洩漏主機內部資料；限速；token 可隨時輪換；唔好用「無認證網址」；repo 唔放主機名、IP、token。

---

## G. 黃金價格

- 來源類型：免費 REST（如 gold-api.com，聲稱免 key）、有 key 嘅（GoldAPI.io、metals.dev，免費額度細）、或 Yahoo 非官方介面（條款灰色，唔建議）。
  **報價多數係「現貨 XAU/USD」，同香港金舖／周大福零售價唔同。**
- 換算：1 金衡安士 ≈ 31.1035 克；香港 1 両 ≈ 37.429 克。USD→HKD 另取匯率。零售價有溢價，widget 只顯示國際現貨參考價。
- 顯示：現價、較上次變動、「更新於 HH:mm」。數據過舊（>1 小時）轉灰。
- 即時性見 B 節：widget 做唔到秒級。

---

## H. 憑證同私隱（必須遵守）

- **Google 憑證、iCal 私人網址、VPS 主機／IP／token、API key** 一律**唔寫入 repo**（包括 `project.yml`、測試、文件）。
- 放置：Keychain（需要 widget 同 app 共用就用 Keychain Access Group）或 App Group UserDefaults（敏感度低嘅設定）；用戶喺 app 設定頁輸入。
- Xcode 版要 `PrivacyInfo.xcprivacy` 宣告用咗嘅 required-reason API（開機時間、磁碟空間、UserDefaults 等）。repo 已有，加新功能時要同步更新。【程式碼】
- 免費 Apple ID 是否支援所需嘅 App Group／Keychain Group：**先用空專案真機試**。【真機待測】

---

## I. 建議實作順序

1. 外觀：改現有 View 配合 Clear／Tinted（零新資料）。
2. 開機 7 日提示＋iOS 最新版本。
3. 日曆（EventKit）＋「明日概要」。
4. 天氣（HKO／Open-Meteo）。
5. 電池估算（需 App Group 取樣）。
6. 黃金＋匯率。
7. VPS 狀態（要先有伺服器端 script）。
8. RAM（低優先）。

每一步都要真機驗證，再將【知識】換成【量度】。

## J. 要問 Ice 嘅嘢

1. 預算：會唔會付 Apple Developer Program（US$99／年）？決定 A 節同 Push／WeatherKit 能否用。
2. 日曆：同意用 iPhone 系統日曆（EventKit）嗎？學校 Google 帳號喺 iPhone 加得入嗎？
3. 「工作更份」資料現時喺邊度（日曆／App／Excel／PDF）？
4. VPS：系統（Ubuntu／Debian／其他）、供應商、可否自行加 cron＋HTTPS endpoint？（唔好喺 repo 或對話貼密碼，之後我會教你喺 app 設定頁輸入。）
5. 地區同天氣：固定香港某區，定要跟 GPS？
6. 黃金：要國際現貨（USD/oz）定香港每両 HKD 參考價？
7. iPhone 型號同 iOS 版本（用嚟核對 Clear 外觀同 widget 尺寸）。
