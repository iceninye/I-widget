# i-widget（Scriptable 並行路徑）

用一隻 Scriptable JavaScript 腳本顯示時鐘、今日摘要、系統資訊、法院案件或鎖屏電量。正常資料路徑係 **Swift app → security-scoped iCloud Scriptable folder → `i-widget.json` → Scriptable Widget**；腳本只讀 JSON，唔連線、唔接收認證資料。

## 架構與並行策略

- Swift app 嘅 `WidgetSnapshotService` 收集更份、資訊、VPS、法院，`WidgetSnapshotBuilder` 轉成 schemaVersion 1 快照。
- `ScriptableBridgeController` 排程，`ScriptableBridgeWriter` 透過 `NSFileCoordinator` atomic write 入授權 folder；`ScriptableFolderStore` 喺 Keychain 保存本機 bookmark。
- app 設定獨有 roster／VPS token 同私人 VPS URL；JSON **唔包含 token、`Authorization` header 或私人 VPS URL**。原生 Widget 仍沿用自己 widget 設定入面嘅 token，唔經 JSON 共享。
- 原生 `iWidgetExtension` 同 `DutyLiveActivity` 保留，通知、AppIntents、Live Activity 不同 Scriptable 取捨。bridge 未授權、離線或寫入失敗只影響同步狀態，唔會阻止原生通知／Live Activity。
- 毋須新增 App Group 或 push entitlement；Live Activity 維持本機更新、`pushType: nil`。

## 安裝與設定

1. iPhone 裝 **Scriptable** 同 **iWidget** app，兩者用同一個 iCloud 帳戶。設定 → Apple Account → iCloud 打開 **Drive**，並開啟 **Scriptable**。
2. 用 Files 進入 **iCloud Drive／Scriptable**。未有 folder 時，可以先喺 Scriptable 執行一次 script，或喺 Files 新增同名 folder。
3. 開 iWidget「設定」→「Scriptable 同步」→「選擇 Scriptable 資料夾」，揀 **Scriptable 資料夾本身**，唔好揀入面子資料夾。app 會保存 security-scoped bookmark；搬移／取代 folder 或授權失效要重新選擇。
4. 喺同一頁揀「Scriptable 主題」：預設、海藍、日落、森林、紫羅蘭或單色，再按「立即寫入 JSON」。主題只影響 Scriptable；原生 Widget 調色風格獨立。
5. 喺 Scriptable 新增 script（例如 `i-widget`），將 [`i-widget.js`](i-widget.js) 全文貼入。更新 script 目前要手動更新，冇自動 loader。
6. Home Screen 長按 → **+** → **Scriptable** → 編輯 Widget：`Script` 揀 `i-widget`，按需要加 `view` parameter。鎖屏亦可加入 Scriptable 行內／圓形／長方形元件。
7. 可選：Scriptable 1.8 加 widget parameter `background=transparent`，只喺 iOS／iPadOS 27.2 或更新版本嘅 Home Screen 透出桌布；較舊系統、鎖屏或冇 parameter 時維持不透明背景。

Scriptable app 內預覽唔代表 widget extension 已經有 iCloud 權限；兩者要分開確認。iOS 首次要求存取 iCloud Drive 時請按允許。Folder 路徑以 `FileManager.iCloud().documentsDirectory()` 為準，唔寫死個人路徑。

如果仍見到舊式時鐘，先確認 Scriptable widget 嘅 `Script` 指向更新後嘅 `i-widget`，以及 `view` parameter 冇明確設做 `clock`。出廠而家預設 `today`；如要時鐘，先明確設定 `view=clock`。另外，改動 repo 入面嘅 JS 唔會自動更新手機 Scriptable script，必須手動貼上全文。

正常路徑唔使預先手放 JSON。手動放一份合法 JSON 可以作進階診斷，但**唔係正常 app bridge**，亦唔可以冒充 Swift 真機匯出驗收。

## `view` 分流

| `view` | 內容 |
| --- | --- |
| `today` | 原生式更份主卡、進度條、天氣、7 日更份色條、明日、學校／假期；有事先先警告 |
| `info` | 儲存空間、開機時間、低耗電、系統版本、環境資訊、VPS、天氣、屯馬綫 |
| `court` | 今日或下一個工作日案件表；只顯示相關案件 |
| `clock` | 小／中／大時鐘、日期、電量；鎖屏 family 用日期／時間／電量 |
| `accessory` | 電量為主的鎖屏式版面；普通 family 顯示電量卡 |

五個 view 都支援 `small`、`medium`、`large`、`extraLarge` 同三個 accessory family；較小尺寸會減少內容。Scriptable app 直接預覽另支援 `previewFamily: "extraLargePortrait"`，呼叫 `presentExtraLargePortrait()`；舊版冇呢個方法時退回 `presentExtraLarge()`。冇 parameter 時用 `CONFIG.previewView`（出廠 `today`）；未知值亦 fallback 到同一個設定。

點選深度連結：`today` → `iwidget://duty`，`info` → `iwidget://info`，`court` → `iwidget://court?code=…`；個別案件帶 `case`／`t` query。`clock`／`accessory` 開啟 `iwidget://duty`。

## 寫入、同步、刷新係三件獨立事

1. **app 寫入成功**：狀態「已寫入，等待 iCloud 同步」只證明 JSON 已落入授權 folder。
2. **iCloud 同步**：由 iCloud／File Provider 決定；app 冇提供同步完成通知，另一部裝置可能仍未見到新檔。
3. **Scriptable Widget 實際刷新**：要 extension 真係執行同重新渲染。app 只直接 reload 原生 Overview／Info timeline，唔保證 Scriptable 何時更新。

有 folder 授權時，Swift `WidgetBackgroundRefresh` 一般以 60 分鐘作為 `BGAppRefreshTaskRequest.earliestBeginDate`；法院發布窗口會提前到 18:45，冇案件時再短重試。Scriptable `refreshAfterDate` 亦以 60 分鐘為一般最早間隔，午夜／01:00 邊界會提前；`view=court` 跟香港時間，工作日 18:45:20 提早 reload，冇案件時 19:00:20 再試、之後 30 分鐘 backoff。呢個 Scriptable 邊界只重讀現有 JSON，**唔會令 app 重新上網或匯出**。app 背景返前景另有 30 分鐘網絡刷新節流，但通知同 Live Activity 仍會用現有資料更新；冷啟、deep link、手動更新同更份邊界保持即時，手動下拉繞過成功快取 TTL。兩者都**唔保證固定間隔**：系統 reload 預算、低耗電、背景排程、iCloud 下載同 extension 啟動都會影響實際時間。

### app 來源 TTL（2026-11-27）

法院非空案件表沿用到下一個發布點；18:30–19:00 空結果每 15 分鐘重試，19:00–20:00 空結果／失敗每 30 分鐘重試，20:00 後沿用到下一個發布點。其他成功快取：天氣警告／港鐵 30 分鐘、黃金 60 分鐘、空氣 2 小時、匯率 12 小時、最新 iOS 24 小時、VPS 60 分鐘、學校日曆 6 小時。天氣一般 60 分鐘、今日卡 10 分鐘去重；更份 basic／sheet 6 小時、cards 12 小時、places 7 日、公眾假期 7 日；通知同 Live Activity 冇獨立網絡 polling。完整對照見 [`../xcode/README.md`](../xcode/README.md)「更新間距記錄」。

**範圍：** 今次只走 Xcode Build → iPhone + Scriptable；ipa 功能擱置，workflow 只移除未審 PR 上 self-hosted runner 嘅入口，Pyto 只封存未驗證遠端拉碼，原生 WidgetKit extension 同通知／AppIntents／Live Activity 保留。

## 有效資料、last-good cache 與新鮮度

1. Scriptable 先向 iCloud 下載、確認存在、讀取 `i-widget.json`。
2. 整份通過驗證後，**先寫入** `FileManager.local().documentsDirectory()/i-widget-last-good.json`，再顯示今次 iCloud 資料。寫 cache 失敗唔會令今次畫面失敗。
3. iCloud 缺失、離線、下載／讀取失敗、JSON 損壞、新 schema 或驗證失敗時，讀 local last-good；無效新檔**唔會覆蓋**有效 cache。
4. cache 都不可用時，`today`／`info`／`court` 顯示「未有資料」同設定提示；`clock`／`accessory` 仍可顯示裝置電量等內容。

FileManager API 或整個 FileManager 缺失都會安全 fallback。正常呼叫形狀為 `downloadFileFromiCloud(path)`、`fileExists(path)`、`readString(path)`、`writeString(path, contents)`；部分版本回傳 Promise，script 用 `await` 兼容。

讀取失敗時，`today`／`info`／`court` widget 會顯示具體階段（下載、`fileExists`、讀取、JSON 驗證或 cache），而唔再靜靜吞錯；喺 Scriptable app 直接執行腳本亦會彈出安全診斷 Alert。診斷只包含階段、系統錯誤訊息同 schema 欄位，不列 JSON 內容、token 或 Authorization header。

`i-widget-last-good.json does not exist` 只表示 local cache 未建立，唔單獨證明 iCloud JSON 缺失。最常見原因係 Scriptable 腳本仍係舊版、widget 未設定 `view`，或者 iCloud JSON 未通過 schema 驗證。

- `serviceDate` 會同香港時間 04:00 轉日後嘅服務日比較；唔同日會顯示「更份日期已過」，唔會將舊更份繼續當「今日」。
- `generatedAt` 只表示 JSON 何時產生，**唔當資料 freshness**。
- `today` 用 `freshness.today`；`info` 用 `freshness.info`；`court` 先用 `freshness.court`，`null` 時退回 `courts.updatedAt`。冇時間就顯示「未有資料」。
- 用 cache 時保留 JSON 內原有 freshness，再加「快取」標記，唔假裝啱啱更新。`system.capturedAt`／`bootAt` 亦只反映快取收集時嘅狀態。`today` 大尺寸天氣行改用 `freshness.weather`（缺少時用 `weather.fetchedAt`），超過 6 小時會以橙色標示「舊」。
- `warnings.available=false` 顯示「未有資料」，不可當成冇警告；`available=true` 而 `items=[]` 先係有效空資料，顯示「沒有警告」。合法空 array 本身唔係損壞。

## 法院語意

- app 以香港時間選案件表：18:30 後可轉到下一個工作日，並跳過週末／公眾假期。Scriptable 只顯示 JSON 內今日或 `courts.listDate` 所指未來日，唔將舊案件表當今日；裝置時間應設為香港時間。
- 今日案件開始後**不足 20 分鐘**標示「進行中」；篩選保留開始後 20 分鐘邊界，正好 20 分鐘會顯示「已過時間」。無 `minutes` 嘅項目不列入今日相關案件。
- app 先篩相關案件再截斷，最多 4 個法院、每個法院 80 宗；被截斷會標記 `truncated`。

## JSON schemaVersion 1

輸入：`FileManager.iCloud().documentsDirectory()/i-widget.json`。完整模型見 [`../xcode/Shared/WidgetExport.swift`](../xcode/Shared/WidgetExport.swift)，主要結構：

```text
schemaVersion: 1
generatedAt: UTC ISO 8601（app 輸出 …Z）
serviceDate: YYYYMMDD
theme: classic | ocean | sunset | forest | violet | mono
freshness: { today, info, schedule, weather, warningsToday, warningsInfo, court }
system: { capturedAt, battery, storage, memory, uptimeSeconds, uptimeText, bootAt,
          systemName, systemVersion, versionText, latestOS, osStatus }
duty: { configured, failed, today, tomorrow, events, week, shiftForecast, weekText, nextHoliday, detailLines }
school: { failed, today, tomorrow }
weather: { available, fetchedAt, currentTemp, today, tomorrow, daily }
warnings: { available, items }
train: { available, stateText, message }
environment: { sections }
vps: { configured, available, failed, lines }
courts: { listDate, updatedAt, items }
```

- App 日期時間以 UTC ISO 8601 輸出；Scriptable 驗證要求帶時區，亦接受合規 `±HH:MM` offset，並檢查真正日曆日期。
- `serviceDate`、`duty.*.date`、`duty.week[].date`、`weather.daily[].date`、`courts.items[].dateCode` 全部係 **YYYYMMDD**。法院原站同快取使用 DDMMYYYY，只有 `WidgetSnapshotBuilder.exportDateCode` 匯出時轉做 YYYYMMDD，唔改原站 URL 或原生 DTO。
- `duty.today/tomorrow` 亦包含更份組別、特別 sheet、改更標記同語義色調 key；`duty.week` 最多 7 日，每格可附當日天氣，用於重現原生更份色條；`duty.shiftForecast` 最多 2 項，用於返工／放工逐小時預報。色調只係顯示資料，唔包含更份 token。舊 app JSON 省略咗 `isOverride`／`tone`／`week`／`shiftForecast` 仍可用基本主卡；一經有新欄位但類型錯誤，仍會整份拒絕。
- 上限 **512 KiB（UTF-8 bytes）**；最多 **4 courts、80 relevant cases／court**。Swift 寫入前檢查大小，Scriptable 亦拒絕越界。
- `freshness` 值係帶時區 ISO 8601 或 `null`；`system.storage.freeBytes`／`totalBytes`、`uptimeSeconds`／`bootAt`、`battery.level`／`lowPowerMode` 可為 `null`；法院 `minutes` 係 `0…1439` 整數或 `null`。缺失數值顯示「未有資料」。
- Swift `JSONEncoder` 省略 `nil` optional key；Scriptable 將省略同 `null` 一樣處理，但主要 object／array／非 optional 欄位仍必須存在。任何主要欄位損壞都整份拒絕，避免半份資料寫入 cache。

## 時鐘邊界與 script 設定

日間用 `applyTimerStyle()`，由今日 00:00 起計，令 iOS 即時跳動 `h:mm:ss`。00:00–00:59 嘅 timer 會變成「分:秒」，所以改用靜態 `applyTimeStyle()`；`nextReload()` 會安排 00:00:20／01:00:20 邊界前 reload。

`i-widget.js` 開頭 `CONFIG`：

- `showBrightness`、`showDayProgress`：只影響 `clock` 大尺寸。
- `reloadMinutes`：一般最早 reload 間隔，預設 60 分鐘；午夜／01:00 正確性邊界仍會提前。
- `previewFamily`、`previewView`：Scriptable app 直接執行時嘅預覽；`previewFamily` 可設 `extraLargePortrait`。
- `transparentBackground`：設 `true` 可預設透明背景；仍受 iOS／iPadOS 27.2+ 同非鎖屏限制。widget parameter `background=transparent` 亦可個別開啟。
- `showRefreshButton`：預設開；iOS／iPadOS 17+ 嘅 `medium`／`large`／`extraLarge`／`extraLargePortrait` 會顯示「重讀」鈕，`today` 唔需要先有未來事件。按鈕只重新執行 Scriptable 同讀取現有 JSON／cache，**唔會令 app 重新上網或匯出**；呢個互動範圍優先於 containing stack 嘅 URL。
- `maxPayloadBytes`、`cacheName`：512 KiB 上限同 `i-widget-last-good.json`。

## Scriptable 1.8 增強

- `clock` 嘅電量、亮度、今日進度同鎖屏圓電量改用原生 `addProgress()`；更份時間條仍保留能精確表示返工至放工區段嘅幾何色條。
- 原生 circular progress 返回 stack 直接承载中間電量文字，唔另加一行，避免鎖屏空間不足。
- 透明背景、重讀鈕同特大直向預覽都按 API／OS／family 檢查；舊 Scriptable 冇 `addProgress` 時用回自製色條，冇 `addRefreshButton` 或 `presentExtraLargePortrait` 時安全略過／fallback。
- 主要更份時間用 `Font.heavyMonospacedSystemFont`，倒數用 `WidgetText.rightAlignText()`；API 不存在時仍有原本字型同對齊 fallback。
- 今日主卡以左至右漸層重現原生色條；七日格等寬，今日格唔會再被固定 28pt 寬度截成「…」。大尺寸補回本週更份摘要，放工後有明日更份或未來「返工」事件就顯示「下一更」倒數。

## 測試與真機驗收

喺 repo 根目錄：

```sh
for zone in UTC Asia/Hong_Kong America/New_York Pacific/Kiritimati; do
  TZ="$zone" node scriptable/test-i-widget.js
done
python3 test_widget.py
python3 test_launcher.py
```

Node 測試不固定程序時區，必須以唔同 `TZ` 開獨立進程；香港法院日期同分鐘使用明確 UTC instant，UTC+14 亦唔可以搶先跟當地時鐘午夜。Node 測試用 fake Scriptable environment，覆蓋 view × family、schema／大小／日期驗證、iCloud 損壞／離線、last-good cache、freshness、法院 20 分鐘邊界、缺資料提示、時鐘邊界同 Device 擲錯；亦覆蓋 1.8 原生進度條、透明背景 OS gate、更新鈕、特大直向預覽、重字型／右對齊同舊 API fallback。Swift 單元測試同 `xcodegen generate`、`xcodebuild test` 指令見 [`../xcode/README.md`](../xcode/README.md)。

自動測試**唔等於真機驗收**。完整「UUID A → app 重啟寫 B」、「飛行模式 cache」、「三項獨立結論」、「原生通知／Live Activity 不受 bridge 影響」清單，見 [`../xcode/README.md`](../xcode/README.md)「真機驗收清單（尚未執行）」。Scriptable stack 對齊、字級、accessory 內容、iCloud bookmark／extension 權限同實際 reload 仍未在真機確認。

## 限制

- Scriptable 本身讀唔到儲存空間、開機時間、低耗電模式；呢三項只來自 JSON，唔使用私有 API。
- 腳本不負責抓資料、不連線、不接收 token；JSON 由已安裝嘅 iWidget app 產生。
- Scriptable stack 嘅寬度、漸變、材質同文字測量能力同 SwiftUI 唔同；`today` 已按原生資訊層級重排，但唔可能保證逐像素一致，最終仍要以真機 widget 為準。
- cache 只係離線應急，唔保證資料新；畫面保留舊 freshness 並標示「快取」。
- iOS 控制 reload；`refreshAfterDate` 唔係截止時間，低耗電或預算耗盡時可明顯延遲。
