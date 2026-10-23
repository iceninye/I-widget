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

> **更新**：Ice 已提供學校公開日曆同 tml-roster，最終設計以 K1、K6 為準；下面係早前嘅一般性分析，EventKit 只作備選。

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

## J. 已確認嘅決定（Ice 回覆）

1. **唔付費**：唔用 TestFlight／Push／WeatherKit。安裝用 Xcode 每 7 日重裝，或 AltStore（見 A 節）。
2. **日曆**：用 iPhone 系統日曆（EventKit），步驟見 K1。
3. **工作更份**：資料來源係 Ice 自己嘅 repo [tml-roster](https://github.com/iceninye/tml-roster)（屯馬綫 Duty Roster），設計見 K6。
4. **VPS**：Ubuntu，步驟見 K2。
5. **天氣**：跟 GPS，定時更新。
6. **黃金**：USD/oz，定時更新。
7. **「即時更新」掣**：加喺 widget 適當位置，見 K3。

### 現況（由 Ice 嘅真機截圖）
Xcode 版已經喺 iOS 27.0.1 真機行得，顯示電量、儲存空間、開機時間、系統版本。
目前 widget 係**純白不透明底**＋灰色卡，未配合 Liquid Glass Clear／Tinted；
所以 C 節嘅外觀改動（去掉不透明底、用階層式顏色）係第一優先。

## K. 實作步驟

### K1. 學校日曆（四個公開 Google 日曆）
Ice 提供咗學校（聖公會聖西門呂明才中學）四個日曆：事項、假期、考試及統測、循環周（Cycle No./Day）。
佢哋係**公開嵌入日曆**（網頁 embed 連結），唔需要登入 Google，所以**唔使 OAuth、唔使 EventKit**，亦冇憑證要保管。

**建議做法：widget 直接讀公開 iCal**
- 每個日曆 ID 解 base64（`src=` 嗰串）得到 `skhsslmc.edu.hk_<隨機碼>@group.calendar.google.com`。
- 公開日曆嘅 iCal 位址格式：`https://calendar.google.com/calendar/ical/<日曆ID（URL 編碼）>/public/basic.ics`。
- widget 抓四條 `.ics`，用細型 iCalendar 解析器（`VEVENT`：`DTSTART`／`DTEND`／`SUMMARY`、全日事件 `VALUE=DATE`、基本 `RRULE`），合併後顯示：
  - 今日：循環周（例如 Day 3）、今日事項。
  - 明日：事項／假期／考試概要（數量＋頭兩項）。
- 好處：無權限彈窗、`即時更新` 掣可以即刻重抓、唔受學校限制 Google 帳號同步影響。
- **未驗證**（我環境封網）：要確認四條日曆係咪「對外公開（See all event details）」令 `/public/basic.ics` 可讀；請 Ice 喺 iPhone Safari 開一條 `.ics` 網址，會自動下載／彈出訂閱就得。
- 備選：如果 `.ics` 讀唔到，喺 iPhone「日曆 → 加入訂閱日曆」貼同一個位址，或者登入學校 Google 帳號，再用 EventKit 讀（需要 `NSCalendarsFullAccessUsageDescription`）。

日曆 ID 係公開資料（學校網頁已公開），放喺 app 設定常數無妨；唔係憑證。

### K2. Ubuntu VPS 狀態
**喺 VPS 上（SSH 入去自己做，唔好將密碼貼出嚟）**
1. 狀態腳本 `/usr/local/bin/vps-status.py`（只讀、唔含任何機密）：
```python
#!/usr/bin/env python3
import json, os, subprocess, datetime
def sh(c): return subprocess.run(c, shell=True, capture_output=True, text=True).stdout
osr = dict(l.strip().split("=", 1) for l in open("/etc/os-release") if "=" in l)
inst = [l for l in sh("apt-get -s dist-upgrade").splitlines() if l.startswith("Inst ")]
out = {
  "os": osr.get("PRETTY_NAME", "").strip('"'),
  "kernel": os.uname().release,
  "upgradable": len(inst),
  "security": sum("security" in l.lower() for l in inst),
  "reboot_required": os.path.exists("/var/run/reboot-required"),
  "updated_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
}
tmp = "/var/www/status/status.json.tmp"
json.dump(out, open(tmp, "w"))
os.replace(tmp, "/var/www/status/status.json")
```
2. `sudo mkdir -p /var/www/status && sudo chmod +x /usr/local/bin/vps-status.py`；用 root crontab 每小時行：`0 * * * * /usr/local/bin/vps-status.py`（`apt-get -s` 係模擬，唔會更新任何套件）。
3. nginx（或 caddy）用 HTTPS 提供 `/var/www/status/status.json`，並要求 `Authorization: Bearer <長隨機 token>`（`openssl rand -hex 32` 產生）；token 只放喺伺服器設定同 iPhone。要有 TLS 證書（例如 Let's Encrypt）。
4. 自己用 `curl -H "Authorization: Bearer …" https://你的網域/status.json` 測試。

**我會做嘅**
- app 設定頁輸入「狀態網址」同 token，存 Keychain／App Group；repo 唔放任何網址或 token。
- widget 顯示 Ubuntu 版本、可更新數、安全更新數、需否重啟；失敗顯示「離線」＋最後成功時間。
- 之後可再加「有冇新 LTS」（`do-release-upgrade -c`，需要 root，另議）。

### K3. 「即時更新」掣
- 用 iOS 17+ 互動 widget：`Button(intent: RefreshIntent())`，放喺 widget 右上角（時鐘旁）一個細圖示＋文字「即時更新」。
- 按下後 intent 重新讀取全部資料（天氣、黃金、VPS、日曆）寫入 App Group 快取，並叫 `WidgetCenter.shared.reloadAllTimelines()`。
- 注意：掣只係「馬上要求更新」，網絡慢或失敗時仍會顯示舊資料；每項資料旁會顯示「更新於 HH:mm」。唔係秒級串流，亦要受系統預算限制（見 B 節）。
- 小 widget 位置有限：掣放喺日期列右邊；鎖屏 widget 唔支援互動掣，唔放。

### K4. 天氣（GPS）
- 加 `NSWidgetWantsLocation`（extension Info.plist）＋ `NSLocationWhenInUseUsageDescription`；app 先要求「使用 App 期間」授權，之後 widget 先可取位置（`isAuthorizedForWidgetUpdates`）。
- 取到位置就寫入 App Group 快取；取唔到用上次位置。位置只用嚟查天氣，不上傳到自己嘅伺服器。
- 天氣每 30 分鐘；今日天氣＋明日預報（最高／最低溫、降雨機率）。資料源：香港用天文台，其他地區用 Open-Meteo（見 D 節）。

### K5. 黃金 USD/oz
- 每 15 分鐘 reload，顯示現價、較上次變動、「更新於 HH:mm」；超過 1 小時轉灰。來源見 G 節，實作前先喺 Mac／iPhone 上核對該 API 免費額度。

### K6. 工作更份（來自 tml-roster）
我睇咗 `tml-roster` repo（只讀）。重點：
- Roster 係 136 行（每行一個星期，週一至週日 7 格），循環；`anchor` 記「某個星期一嗰週做第幾行」。格內容：7 位更份編號（頭 4 位係 Duty Sheet：1101 平日、6091 星期六、7091 星期日）、`RD`／`AL`／`SH`／`HC`、後備更 `HSP1`／`KSP1…`；另有「某日手動改」`overrides`。
- 服務日由香港時間 **04:00** 轉日（00:30 前後收工仍算前一日）。
- 更份上落班時間：TML-traffic 嘅 `data/duty-basic.json`，格式 `"1100101":[上班秒,"地點",下班秒,"地點",工時,"DE/DL"]`（秒數由服務日 00:00 起計，可超過 86400）。特別日子（8022／8023／8027／7091M）要睇 `data/duties/index.json` 嘅 `dates`／`alsoOn`。
- 你嘅更表**只存喺瀏覽器**；有雲端同步：`tml-roster` 嘅 Cloudflare Worker `GET /api/roster/<token>` 回傳完整 roster（rows／numbers／anchor／overrides）。token 係 20–64 位 `[a-z0-9]`，「靠 URL 保密」——**攞到條 URL 嘅人讀寫得到**。

**widget 設計**
1. app 設定頁輸入 tml-roster 嘅同步 token（或者貼上「設定／備份」匯出嘅 JSON），存 Keychain／App Group；**token 同 roster 內容絕不寫入 repo、測試、文件**（`tml-roster` 自己亦咁規定）。
2. widget 唯讀：每日抓一次 roster（`GET`，唔 `PUT`），快取落 App Group；`duty-basic.json` 同 `index.json` 由 TML-traffic 讀（同 tml-roster 一樣先試 `tml-traffic.iceninye.workers.dev`，再試 GitHub raw）。
3. 用 Swift 移植 `lib/tml-roster.js` 嘅 `rowAfter`／`dayEntry`／`serviceDate`（約 100 行純函數），並照搬 `tools/validate_roster.mjs` 嘅虛構 roster 做 XCTest 對照測試。
4. 顯示：今日更份編號＋類別（死早／早／中／夜／死夜，按 `lib/tml-shift.js`：06:30 前上班＝死早，00:30 後下班＝死夜，其餘按 10:00／15:00 分早／中／夜）、上班／下班時間同地點；明日同樣。`RD`／`AL`／`SH` 顯示「休息」「年假」「公眾假期」。
5. 風險：(a) token 若外洩，roster 會被讀寫，widget 只做 `GET`，但 token 要放 Keychain；(b) 雲端同步係 Ice 手動開啟先有，冇 token 就用貼上 JSON；(c) widget 抓取失敗要顯示上次快取＋「更新於」。

### K7. 實際 VPS（Hostinger，Ubuntu，Docker＋Traefik）
**已部署並驗證（2026-10-23，Ice 真機伺服器）**：無 token 回 401，帶 token 回 200。
- 80/443 由 Docker 內嘅 Traefik 管（Let's Encrypt，`mytlschallenge`），所以唔用主機 nginx。
- Traefik 原本 3.4.1 同 Docker 29.9.2 不相容（`client version 1.24 is too old`，所有路由 404），已升級 Traefik 鏡像。
- 狀態端點 = `nginx:alpine` 容器（`/opt/status`，compose 專案 `status`），Traefik 標籤路由 `Host(<現有主機名>) && Path(/status.json)`，優先級 100；nginx 用 `map` 檢查 `Authorization: Bearer <token>`，`map_hash_bucket_size 128`。
- 狀態腳本 `/usr/local/bin/vps-status.py`（root cron 每小時）輸出 OS、kernel、可更新數、安全更新數、需否重啟、`xray_running`、`hysteria2_listening`（Hysteria2 係 Xray 嘅 UDP 8443 inbound）。
- n8n 已停並設 `--restart=no`（對外頁面關閉）；Redis／Postgres 暫留。
- 主機名、token 唔寫入 repo；步驟文件在專案檔案 `widget/vps-status-setup.md`。
- 下游 widget 設定：app 設定頁輸入「狀態網址」同 token（Keychain／App Group）。

## L. 仍要問 Ice

1. **tml-roster 同步 token**：widget 要讀你嘅雲端 roster，需要你喺 app 設定頁自己輸入（唔好貼喺 chat）。你想用「雲端同步 token」，定係貼匯出嘅備份 JSON（離線，要手動更新）？
2. **學校日曆**：請喺 iPhone Safari 開四條公開 `.ics` 之一確認可讀（見 K1）；如果唔得，我會轉用「訂閱日曆＋EventKit」。
3. **VPS**：請喺 VPS 按 K2 同 K7 部署狀態腳本同 nginx，完成後話我知（只要講「做咗」，唔使貼 token）。
