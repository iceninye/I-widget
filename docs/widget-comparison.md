# 四種 widget 實作比較

比較對象（Ice 指定嘅四種：py、js、py+js、xcode。其中 py+js 仍處於**驗證階段，repo 內未有實作**，見第 6 節）：

| # | 名稱 | 檔案 | 語言／平台 |
| --- | --- | --- | --- |
| A | Pyto 本地版 | `i_widget.py` | Python，喺 Pyto 嘅 widget extension 行 |
| B | Pyto 自動更新版 | `i_widget_launcher.py` + `i_widget.py` | 同 A，但 launcher 每次 reload 向 GitHub 攞最新版 |
| C | Scriptable 版 | `scriptable/i-widget.js` | JavaScript，喺 Scriptable 行 |
| D | 原生 Xcode 版 | `xcode/` | Swift／SwiftUI／WidgetKit |

> A 同 B 共用同一份 widget 本體，分別只係「點樣攞到程式碼」，所以版面、資料、耗電幾乎一樣，
> 下面除咗安裝同維護兩項，A／B 會合併講。

## 點樣睇「量度」同「估計」

呢份文件每個結論都標明依據：

- **【真機】** 喺真 iPhone 上確認過（見 `docs/POSTMORTEM.md` 同 README 嘅真機足跡／截圖紀錄）。
- **【CI】** GitHub Actions 自動驗證過（Tests：mock 環境 smoke test；iOS build：macOS runner 編譯＋XCTest）。
  CI 通過只代表「編譯得、邏輯測試過」，**唔代表**真機畫面同行為正確。
- **【程式碼】** 直接睇程式碼得出，可核對，但未實測。
- **【估計】** 按 Apple／平台一般行為推斷，**冇量度**。

**重要**：repo 入面**冇任何耗電、記憶體或 reload 成功率嘅實測數據**。所有「耗電」「穩定性」嘅比較都係【程式碼】＋【估計】，
唔好當成 benchmark。Scriptable 版同 Xcode 版亦**未喺真機驗證過**（只有 A／B 有真機紀錄）。

## 驗證程度一覽

| | A/B Pyto | C Scriptable | D Xcode |
| --- | --- | --- | --- |
| 真機運行過 | 是（修完 `DynamicDate` 問題後 widget 正常顯示）【真機】 | 否（README 明講未試）| 否（repo 內冇紀錄）|
| CI 自動測試 | `test_widget.py`、`test_launcher.py`（mock Pyto）| `test-i-widget.js`（假 Scriptable，46 項）| macOS runner 編譯＋ XCTest（最近一次 main：成功）|
| 已知真機事故 | 有：綠色 default template（`DynamicDate(color=…)` 令 process 被殺），已修 | 未知 | 未知 |

## 1. 版面質素同彈性

**A/B Pyto** — 小／中／大（iPad 另有 extra large）。排版工具只有「一行行 + Spacer」
`layout.add_row([...])`，無真正 stack，進度條用 `▰▱` 文字字元模擬，圓角卡用 `add_row(background_color, corner_radius)`。
Tinted／clear 等 iOS 27 渲染模式 Pyto 冇 API 控制。冇鎖屏 widget。【程式碼】
真機上版面已確認出到畫面，但曾出現過貼邊、冇靠右等問題，之後逐步修。【真機】
另一個代價：任何元件都可能令 process 被殺，所以程式碼加咗大量崩潰偵測／繞開邏輯（`i_widget.py` 853 行）。【程式碼】

**C Scriptable** — 有真正 `WidgetStack`、固定大小 stack（畫真進度條）、`Color.dynamic`，
支援鎖屏三款（行內／圓形／長方形）。337 行。【程式碼】
彈性明顯高過 Pyto，但仍然係 Scriptable 提供嘅元件集（冇自訂 SwiftUI 動畫、Gauge、Charts）。【估計】
計時器樣式實際顯示（`1:30:15` 定 `01:30:15`）未經真機確認。

**D Xcode** — 完整 SwiftUI：小／中／大／extra large ＋ 鎖屏三款，`Gauge`（`accessoryCircularCapacity`）、SF Symbols、
`containerBackground`、原生 tinted／clear 渲染。【程式碼】
彈性最高，亦係唯一能夠跟 iOS 新 widget family／渲染模式嘅版本（Pyto 同 Scriptable 要等第三方 app 更新）。【估計】

結論：**D > C > A/B**。

## 2. 資料存取能力

| 資料 | A/B Pyto | C Scriptable | D Xcode |
| --- | --- | --- | --- |
| 電量／充電中 | ✅（UIDevice，失敗退 IOKit；extension 內有機會顯示 `—`）【程式碼】 | ✅ `Device.batteryLevel()` | ✅ `UIDevice` |
| 儲存空間（同設定一致）| ✅ `NSURLVolumeAvailableCapacityForImportantUsageKey`，真機讀到 32／255 GB【真機】 | ❌ 無 API | ✅ 同款 key【程式碼】 |
| 開機時間 | ✅ `kern.boottime`【程式碼】 | ❌ | ✅ `sysctl kern.boottime`【程式碼】 |
| 低耗電模式 | ✅ | ❌ | ✅ `isLowPowerModeEnabled` |
| 系統版本 | ✅ | ✅ | ✅ |
| 螢幕亮度 | — | ✅（補位）| — |
| 網絡存取 | ✅（launcher 靠佢自更新）| ✅（`Request`，但目前冇用）| ✅（可加，但現有碼冇用）|

重點：**Scriptable 讀唔到儲存空間、開機時間、低耗電模式**（README 已核對型別定義 `@types/scriptable-ios` 1.7.9），
所以呢三項喺 C 缺席，只能用螢幕亮度／今日進度補位。Pyto 靠 `rubicon.objc` 直接叫 ObjC，所以讀得到，
但係靠 ctypes／ObjC 橋接，比原生脆弱（見 POSTMORTEM）。Xcode 版有完整系統 API，將來要加 App Group、
HealthKit、天氣等亦只有 D 做得到（需要簽名／權限）。【估計】

## 3. 耗電同資源使用

**冇實測數據。** 以下純粹依實作結構推斷：

- **A/B Pyto**：每次 reload 都要喺 extension 入面啟動 CPython ＋ rubicon，extension 有嚴格 RAM 上限，
  真機已發生過 process 被殺（綠色事故）。程式碼已將 extension 工作減少（iPhone 唔砌 extra large、減 userkeys 寫入），
  但啟動成個直譯器嘅固定成本仍在。B 另外每 30 分鐘最多一次網絡請求（指紋檔只有 17 bytes；有變先下載十幾 KB 程式碼）。【程式碼】【估計：單次 reload 比 C、D 重】
- **C Scriptable**：JavaScript 引擎（JavaScriptCore）較輕；時鐘用 `applyTimerStyle()` 交俾 iOS 渲染，唔使靠 reload。【程式碼】【估計：輕過 Pyto，重過原生】
- **D Xcode**：原生 Swift 編譯碼，每次 `getTimeline` 只做幾個系統呼叫。【程式碼】【估計：三者最輕】

三者時鐘都係「交俾系統自己跳」（Pyto／Scriptable 用計時器樣式 date；Xcode 用每分鐘一個 timeline entry，entry 切換不計 reload 預算），
其餘資料每 30 分鐘重讀（一日 48 次，貼近 Apple 一般預算）。所以**持續耗電差距主要來自每次 reload 嘅啟動成本**，
而唔係時鐘本身。【程式碼】

## 4. 更新（refresh）可靠性

- **共通限制**：iOS 決定幾時真正 reload，`refreshAfterDate`／`.atEnd` 只係「唔早於」。低耗電模式、預算用完都會延遲。【估計】
- **A/B Pyto**：reload 靠 Pyto 嘅 `schedule_next_reload`。計時器 date 喺 00:00–00:59 會顯示成「分:秒」，
  所以 00:xx 改用靜態 `HH:MM` 並安排 00:00／01:00 reload。真機出過 process 被殺、outdated cache 鎖死 widget
  （POSTMORTEM），都已加自癒，但**呢類問題證明 Pyto 路線有較高嘅「無聲失敗」風險**。【真機】
  電量有機會因 extension 權限讀唔到而顯示 `—`。
- **C Scriptable**：邏輯同 Pyto 類似（`refreshAfterDate` ＋計時器邊界）；Scriptable widget 要由 Scriptable 嘅 extension 執行，
  script 出錯會顯示空白／錯誤。有 `safe()` 包住讀取，讀唔到唔 crash。【程式碼】未真機驗證。
- **D Xcode**：標準 WidgetKit Timeline，每次 30 個每分鐘 entry、`.atEnd`；冇直譯器，冇「process 被殺」類型嘅額外風險。【程式碼】
  iOS 預先收到 30 個 entry，即使 reload 延遲，時鐘仍會按 entry 時間切換。【估計】

結論：**D 最可靠**；A/B 有真機事故紀錄；C 未知，預期介乎中間。

## 5. 安裝同維護

| | A Pyto 本地 | B Pyto 自動更新 | C Scriptable | D Xcode |
| --- | --- | --- | --- | --- |
| 需要 Mac | 否 | 否 | 否 | **是**（Xcode 15+、XcodeGen）|
| 額外 App | Pyto | Pyto | Scriptable | 無（自己嘅 app）|
| 費用 | Pyto 要買（以 App Store 為準）| 同左 | Scriptable 免費（以 App Store 為準）| 免費 Apple ID 可用；TestFlight／上架需付費開發者帳號【估計，請以 Apple 現行規定為準】|
| 簽名過期 | 無 | 無 | 無 | 免費 Apple ID **7 日過期**，要重新接機 Run；付費帳號一年 |
| 更新程式碼 | 手動抄入 Pyto | **自動**（指紋＋SHA256＋語法檢查＋快取）| 手動貼入（README 提過可加 loader，未實作）| 重新編譯安裝 |
| 出錯時可見性 | 難診斷（要睇足跡）| 同左，另有「更新失敗」畫面 | Scriptable 內可直接行／睇錯 | Xcode debugger、unit test |
| 自動測試 | mock 環境 | mock 環境（72 項）| 假 Scriptable（46 項）| macOS CI 編譯＋ XCTest |
| 維護成本 | 高（要追 Pyto 版本 bug、崩潰繞開）| 高＋launcher | 低 | 中（Apple SDK 升級、簽名）|

關於 TestFlight：D 如果用 TestFlight 發佈，要付費 Apple Developer Program 帳號，
build 90 日過期但可以重新上傳；好處係唔使每 7 日接機，亦可分享俾其他人。【估計，請以 Apple 現行規定為準】
免費 Apple ID 就只能 Xcode 直接安裝（7 日）。

## 6. py+js 混合方案（設計階段，未實作、未驗證）

> **決定（Ice）：可靠性低過 Scriptable 同 Xcode，所以不再考慮 py+js。** 以下只保留作紀錄。

另一條 thread 提出：Pyto 做「收集器」讀儲存空間、開機時間、低耗電模式，寫 JSON 去 iCloud 嘅 Scriptable 資料夾；
Scriptable 讀 JSON，同電量、時鐘一齊砌 widget，並顯示「更新於 HH:MM」。目的係補返 Scriptable 缺嘅三項資料，同時用 Scriptable 嘅排版。

**以下全部係【估計】／設計，冇任何真機結果：**

- 優點：版面同鎖屏用 Scriptable（C 嘅強項），資料補齊（A 嘅強項）；Pyto 只做短時間背景任務，唔使喺 extension 砌 UI，避開綠色事故嗰類問題（但呢條路 Pyto 背景收集器本身未驗證）。
- 風險 1：Pyto 背景更新（`background.request_background_fetch()`）由系統決定幾時行、最多約 30 秒，源碼自己都寫「唔可靠」；低耗電模式可能令佢完全唔行。
- 風險 2：iCloud 同步有延遲，多咗兩個 app 之間嘅環節同出錯位。
- 風險 3：要同時裝、維護兩個 app，安裝步驟最多（Pyto 要揀資料夾授權）。
- 緩解：存「來源」唔存「數值」——例如存開機時間戳，由 Scriptable 計「而家 − 開機時間」，資料舊都準；儲存空間舊幾個鐘可接受並附更新時間；低耗電只有收集器跑過嗰刻先準，可標示時間或不顯示。
- 驗證計劃：先喺 Pyto 行寫入 probe、Scriptable 讀取 probe，記錄「背景跑咗幾次」（建議關／開低耗電各測一日），通過先寫正式版。

暫定位置：資料齊全度接近 A，版面接近 C，可靠性**低過 C，亦低過 D**（多咗背景同步環節）；驗證結果出嚟前唔評分。

## 總結評分（1–5，越高越好；分數係主觀判斷，依上面證據）

| 項目 | A/B Pyto | C Scriptable | D Xcode |
| --- | --- | --- | --- |
| 版面質素同彈性 | 2 | 4 | 5 |
| 資料存取 | 4 | 2 | 5 |
| 耗電／資源 | 2 | 3 | 5 |
| 更新可靠性 | 2 | 3 | 5 |
| 安裝簡易（無 Mac）| 4 | 5 | 2 |
| 長期維護 | 2 | 4 | 4 |

## 建議

1. **有 Mac、想長期穩定用 → 揀 D（Xcode）。** 資料最齊、版面最好、最少「無聲失敗」。
   代價：免費帳號 7 日要重新安裝；想免除就要付費開發者帳號＋ TestFlight。
2. **冇 Mac／唔想簽名 → 揀 C（Scriptable）。** 排版同鎖屏比 Pyto 好，維護輕；
   但接受冇儲存空間、開機時間、低耗電模式。最值得補嘅係加自動更新 loader。
3. **py+js** 已決定不再考慮（可靠性低）。要補資料就直接用 D。
4. **A/B（Pyto）建議降為後備。** 資料齊全而且 B 有自動更新，但 Pyto 路線嘅 extension 限制令佢最容易無聲失敗（已有真機事故），
   維護成本最高。只有「一定要儲存空間／開機時間又冇 Mac」先值得留。
5. **下一步要真正分高低：** 將 C、D 都放上真機，連續跑幾日，記錄實際 reload 次數、時鐘有冇停、
   電量百分比消耗（設定 → 電池 → 按 app 用量），先可以將上面【估計】變成【量度】。
