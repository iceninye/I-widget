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

Scriptable app 內預覽唔代表 widget extension 已經有 iCloud 權限；兩者要分開確認。iOS 首次要求存取 iCloud Drive 時請按允許。Folder 路徑以 `FileManager.iCloud().documentsDirectory()` 為準，唔寫死個人路徑。

正常路徑唔使預先手放 JSON。手動放一份合法 JSON 可以作進階診斷，但**唔係正常 app bridge**，亦唔可以冒充 Swift 真機匯出驗收。

## `view` 分流

| `view` | 內容 |
| --- | --- |
| `today` | 今日更份、學校日程、天氣／警告、屯馬綫 |
| `info` | 儲存空間、開機時間、低耗電、系統版本、環境資訊、VPS、天氣、屯馬綫 |
| `court` | 今日或下一個工作日案件表；只顯示相關案件 |
| `clock` | 小／中／大時鐘、日期、電量；鎖屏 family 用日期／時間／電量 |
| `accessory` | 電量為主的鎖屏式版面；普通 family 顯示電量卡 |

五個 view 都支援 `small`、`medium`、`large`、`extraLarge` 同三個 accessory family；較小尺寸會減少內容。冇 parameter 時用 `CONFIG.previewView`（出廠 `clock`）；未知值亦 fallback 到同一個設定。

點選深度連結：`today` → `iwidget://duty`，`info` → `iwidget://info`，`court` → `iwidget://court?code=…`；個別案件帶 `case`／`t` query。`clock`／`accessory` 開啟 `iwidget://duty`。

## 寫入、同步、刷新係三件獨立事

1. **app 寫入成功**：狀態「已寫入，等待 iCloud 同步」只證明 JSON 已落入授權 folder。
2. **iCloud 同步**：由 iCloud／File Provider 決定；app 冇提供同步完成通知，另一部裝置可能仍未見到新檔。
3. **Scriptable Widget 實際刷新**：要 extension 真係執行同重新渲染。app 只直接 reload 原生 Overview／Info timeline，唔保證 Scriptable 何時更新。

有 folder 授權時，Swift `WidgetBackgroundRefresh` 會以 30 分鐘作為 `BGAppRefreshTaskRequest.earliestBeginDate`；Scriptable `refreshAfterDate` 亦以 30 分鐘為一般最早間隔，午夜／01:00 邊界會提前。兩者都**唔保證固定間隔**：系統 reload 預算、低耗電、背景排程、iCloud 下載同 extension 啟動都會影響實際時間。

## 有效資料、last-good cache 與新鮮度

1. Scriptable 先向 iCloud 下載、確認存在、讀取 `i-widget.json`。
2. 整份通過驗證後，**先寫入** `FileManager.local().documentsDirectory()/i-widget-last-good.json`，再顯示今次 iCloud 資料。寫 cache 失敗唔會令今次畫面失敗。
3. iCloud 缺失、離線、下載／讀取失敗、JSON 損壞、新 schema 或驗證失敗時，讀 local last-good；無效新檔**唔會覆蓋**有效 cache。
4. cache 都不可用時，`today`／`info`／`court` 顯示「未有資料」同設定提示；`clock`／`accessory` 仍可顯示裝置電量等內容。

FileManager API 或整個 FileManager 缺失都會安全 fallback。正常呼叫形狀為 `downloadFileFromiCloud(path)`、`fileExists(path)`、`readString(path)`、`writeString(contents, path)`；部分版本回傳 Promise，script 用 `await` 兼容。

- `generatedAt` 只表示 JSON 何時產生，**唔當資料 freshness**。
- `today` 用 `freshness.today`；`info` 用 `freshness.info`；`court` 先用 `freshness.court`，`null` 時退回 `courts.updatedAt`。冇時間就顯示「未有資料」。
- 用 cache 時保留 JSON 內原有 freshness，再加「快取」標記，唔假裝啱啱更新。`system.capturedAt`／`bootAt` 亦只反映快取收集時嘅狀態。
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
duty: { configured, failed, today, tomorrow, events, weekText, nextHoliday, detailLines }
school: { failed, today, tomorrow }
weather: { available, fetchedAt, currentTemp, today, tomorrow, daily }
warnings: { available, items }
train: { available, stateText, message }
environment: { sections }
vps: { configured, available, failed, lines }
courts: { listDate, updatedAt, items }
```

- App 日期時間以 UTC ISO 8601 輸出；Scriptable 驗證要求帶時區，亦接受合規 `±HH:MM` offset，並檢查真正日曆日期。
- `serviceDate`、`duty.*.date`、`weather.daily[].date`、`courts.items[].dateCode` 全部係 **YYYYMMDD**。法院原站／DTO 使用 DDMMYYYY，只有 `WidgetSnapshotBuilder.exportDateCode` 匯出時轉做 YYYYMMDD，唔改原站 URL 或 DTO。
- 上限 **512 KiB（UTF-8 bytes）**；最多 **4 courts、80 relevant cases／court**。Swift 寫入前檢查大小，Scriptable 亦拒絕越界。
- `freshness` 值係帶時區 ISO 8601 或 `null`；`system.storage.freeBytes`／`totalBytes`、`uptimeSeconds`／`bootAt`、`battery.level`／`lowPowerMode` 可為 `null`；法院 `minutes` 係 `0…1439` 整數或 `null`。缺失數值顯示「未有資料」。
- Swift `JSONEncoder` 省略 `nil` optional key；Scriptable 將省略同 `null` 一樣處理，但主要 object／array／非 optional 欄位仍必須存在。任何主要欄位損壞都整份拒絕，避免半份資料寫入 cache。

## 時鐘邊界與 script 設定

日間用 `applyTimerStyle()`，由今日 00:00 起計，令 iOS 即時跳動 `h:mm:ss`。00:00–00:59 嘅 timer 會變成「分:秒」，所以改用靜態 `applyTimeStyle()`；`nextReload()` 會安排 00:00:20／01:00:20 邊界前 reload。

`i-widget.js` 開頭 `CONFIG`：

- `showBrightness`、`showDayProgress`：只影響 `clock` 大尺寸。
- `reloadMinutes`：一般最早 reload 間隔，預設 30 分鐘；午夜／01:00 邊界會提前。
- `previewFamily`、`previewView`：Scriptable app 直接執行時嘅預覽。
- `maxPayloadBytes`、`cacheName`：512 KiB 上限同 `i-widget-last-good.json`。

## 測試與真機驗收

喺 repo 根目錄：

```sh
node scriptable/test-i-widget.js
python3 test_widget.py
python3 test_launcher.py
```

Node 測試用 fake Scriptable environment，覆蓋 view × family、schema／大小／日期驗證、iCloud 損壞／離線、last-good cache、freshness、法院 20 分鐘邊界、缺資料提示、時鐘邊界同 Device 擲錯。Swift 單元測試同 `xcodegen generate`、`xcodebuild test` 指令見 [`../xcode/README.md`](../xcode/README.md)。

自動測試**唔等於真機驗收**。完整「UUID A → app 重啟寫 B」、「飛行模式 cache」、「三項獨立結論」、「原生通知／Live Activity 不受 bridge 影響」清單，見 [`../xcode/README.md`](../xcode/README.md)「真機驗收清單（尚未執行）」。Scriptable stack 對齊、字級、accessory 內容、iCloud bookmark／extension 權限同實際 reload 仍未在真機確認。

## 限制

- Scriptable 本身讀唔到儲存空間、開機時間、低耗電模式；呢三項只來自 JSON，唔使用私有 API。
- 腳本不負責抓資料、不連線、不接收 token；JSON 由已安裝嘅 iWidget app 產生。
- cache 只係離線應急，唔保證資料新；畫面保留舊 freshness 並標示「快取」。
- iOS 控制 reload；`refreshAfterDate` 唔係截止時間，低耗電或預算耗盡時可明顯延遲。
