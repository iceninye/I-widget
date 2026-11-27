# i-widget 原生 Xcode 專案：安裝到 iPhone

需要：Mac、Xcode 15 或以上、iPhone（iOS 17+）、USB 線、Apple ID（免費即可）。

## 架構與並行策略

Swift app 同時支援原生 WidgetKit 同 Scriptable，兩者並行：

- **原生 Widget**：`iWidgetExtension` 提供今日咭、各項資訊、法院案件；同 extension 內嘅 `DutyLiveActivity` 必須保留。通知、AppIntents、更份倒數唔依賴 Scriptable。
- **Scriptable**：`WidgetSnapshotService` 收集更份／資訊／VPS／法院 → `WidgetSnapshotBuilder` 正規化 → `ScriptableBridgeController` 排程 → `ScriptableBridgeWriter` 對授權 folder 做 coordinated atomic write，寫入 `i-widget.json`。`scriptable/i-widget.js` 只讀 JSON，唔連線。
- **授權**：`ScriptableFolderStore` 用 Keychain 保存 device-only folder bookmark；每次寫入先 resolve bookmark，再 `startAccessingSecurityScopedResource()`。搬走／取代 folder 或 bookmark 失效要重新授權。
- **背景**：`WidgetBackgroundRefresh` 喺有授權時排 `BGAppRefreshTask`，到期獨立匯出；前景落背景亦會嘗試 flush。

app 設定獨有 roster／VPS token 同私人 VPS URL，保存在 device-only Keychain（`AfterFirstUnlockThisDeviceOnly`）；舊版 `UserDefaults` 值會自動遷移，成功後先刪除明文。JSON 唔包含 token、`Authorization` header 或私人 VPS URL。原生 Widget 仍沿用自己「編輯小工具」入面嘅 token，唔係由 Scriptable JSON 共享。橋樑未授權、斷線或寫入失敗只影響同步狀態，`AppModel.refresh()` 仍會排通知／同步 Live Activity；唔可以為咗 Scriptable 刪 extension 或改壞原生功能。

`project.yml` 沿用本機 Live Activity、`fetch` background mode 同 Scriptable refresh BGTask identifier；**毋須新增 App Group 或 push entitlement**，`pushType` 維持 `nil`。

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
   保留 `iWidgetExtension`；Scriptable bridge 唔使 App Group、push 或其他新 entitlement。

## 3. 安裝
1. iPhone 用線接 Mac，解鎖並㩒「信任此電腦」。
2. iPhone：設定 → 隱私權與安全性 → **開發者模式** → 開啟，然後重新啟動。
3. Xcode 上方 scheme 揀 **iWidget**，裝置揀你部 iPhone，㩒 **Run (⌘R)**。
4. 第一次會提示「不受信任嘅開發者」：設定 → 一般 → **VPN 與裝置管理** → 揀你個 Apple ID → 信任。再 Run 一次。

## 3b. 用 AltStore 安裝（唔使每 7 日插線）

> 2026-11-27：ipa／AltStore 路線暫時擱置，今次 PR 只喺 ipa workflow 移除未審 PR 嘅 self-hosted 入口，冇恢復 ipa 流程；以下保留作舊資料。目前驗收路線係上方 Xcode Build → iPhone + Scriptable。

免費 Apple ID 簽名 7 日就過期。AltStore 會喺 Mac／PC 嘅 AltServer 同 iPhone 喺同一個 WiFi 時自動重新簽名，唔使再用 Xcode 重裝。

1. Mac 裝好 AltServer、iPhone 裝好 AltStore（照 AltStore 官方步驟，用你自己嘅 Apple ID）。
2. 用 iPhone 嘅 Safari 開 <https://github.com/iceninye/I-widget/releases/download/ipa-latest/iWidget.ipa> 下載（GitHub Actions `Build ipa` 每次 main 嘅 `xcode/` 有改動就更新呢個 Release，檔案係**未簽名**，所以 AltStore 先可以用你個 Apple ID 簽）。
3. 下載完用「分享」→ **AltStore**（或者 AltStore → My Apps → 左上角 **+** → 揀檔案）。
4. 之後 AltServer 開住、同一個 WiFi，AltStore 會自動續期；有新版本就重複步驟 2、3，AltStore 會直接覆蓋更新。

注意：
- **先刪走 Xcode 裝嗰個舊 app。** AltStore 會喺 bundle id 後面加你個 Team ID（Extension 一齊改），所以同 Xcode 版係兩個唔同嘅 app；本 repo 嘅 bundle id（`com.iceninye.i-widget`）唔使改。
- **設定要重新填**：roster token、交接提示設定、通知權限、每個 widget「編輯小工具」入面嘅 token（VPS token 等），同捷徑 App 入面「排交接提示」自動化（重新揀動作）。
- 呢個 app 冇用 App Group 或其他 entitlement，所以重新簽名唔會令功能消失。
- 免費帳戶 App ID 有數量限制（app + widget extension 用 2 個）；仍然係 7 日簽名期，只係自動續期。

## 4. 加 widget
主畫面長按 → 左上角 **+** → 搵 **i-widget**，有三個 widget（各自加、各自設定）：
- **今日咭**（中／大）：今日更份（頭行有服務日日期）、天氣預報（而家溫度、天氣、高低溫、降雨機會，加返工／放工嗰個鐘嘅逐小時預報）、
  天氣警告同屯馬綫狀況、未來 7 日（每日更份 + 天氣）、本週概況、明日、學校日程。長按 →「編輯小工具」填 tml-roster 同步 token。
  天氣用 Open-Meteo（免 key），同「各項資訊」共用 10 分鐘快取。讀唔到天氣／警告／列車資料會寫「未有資料」，唔會當成冇警告或者正常。
  位唔夠時逐級讓位：先收「本週概況」、更份提示同逐小時預報，再收假期行、7 日色條、明日，**學校日程最尾先收**
  （順序喺 `Shared/TodayPlan.swift`，有單元測試；之前係先收學校，搞到大格 widget 底部留一大舊空白、學校完全唔見）。
  學校自己會先減到 3 行、再減到 1 行，裝唔晒嘅寫「另有 N 項」，今明兩日真係冇活動就寫「今明兩日冇學校活動」。
  主要更份、倒數同警示保留，字級唔會縮細。撳更份主體或者天氣行都可以反轉睇詳情。
  排咗更（正常更／後備更）但上落班時間讀唔到時，會用細字寫「上落班時間未有資料」，唔會當成休息日；休息／假期／待定照舊。
- **各項資訊**（大）：天氣警告、屯馬綫、電量、儲存、開機、天氣、黃金（港元每両，背面有每克同國際價）、系統版本、紫外線、空氣、匯率、記憶體（一刻快照）、降雨機會、低耗電模式、VPS。位唔夠會由最底一行開始收起。長按 →「編輯小工具」填 VPS token
  （唔使打 `Bearer`）；VPS 網址已預設 `https://n8n.itswong.site/status.json`，留空就得。
- **法院案件表**（大）：司法機構法庭日誌（e-services.judiciary.hk/dcl），長按 →「編輯小工具」揀最多 4 個法院。
  每個法院先列全日分類統計（刑事、民事、家事、上訴、審裁處、死因），再逐個聆訊兩行顯示：時間、案號、法庭；
  類別（行頭色條同標籤）、案件類型（按案號前綴推斷，例如 DCCJ = 民事訴訟、KCCC = 刑事案件）· 聆訊性質（答辯、訊問、審訊…）、法官。
  聆訊性質只認固定字眼，唔會誤把被告姓名或者控罪當成性質。
  撳法院標題或者任何一行會打開 app「法院」分頁：撳行直接開聆訊詳情，撳標題跳去該法院。唔顯示訴訟各方（網站話明個人資料不可再用）。18:30 後轉睇下一個工作天。
  App 內「法院」分頁可以揀法院、按類別篩選、搜尋案號／法庭／法官／類型，每個聆訊有詳情頁（案件類型、聆訊性質、複製案號、開原案件表網頁）。
  三個 widget 嘅更新時間都係最後成功取得**自己會畫嘅**資料嘅時間，唔係最後嘗試時間；今日咭唔會因為「各項資訊」啱啱讀過黃金／匯率就顯示已更新（天氣警告嘅成功時間亦按 widget 分開記）。下載失敗沿用快取時唔會冒充啱啱更新，從來冇成功記錄就顯示「未有資料」。

Token 係各個 widget 自己儲存嘅，所以拆咗之後，「各項資訊」要重新填一次 VPS token。

## 4b. Swift app → Scriptable（同原生 Widget 並行）

1. iPhone 設定 → Apple Account → iCloud 打開 **Drive**，亦要開啟 **Scriptable**。app 同 Scriptable 用同一個 iCloud 帳戶。
2. 用 Files 進入 **iCloud Drive／Scriptable**。未有 folder 時，可以先喺 Scriptable 跑一次 script 或喺 Files 新增同名 folder。
3. 開 iWidget「設定」→「Scriptable 同步」→「選擇 Scriptable 資料夾」，揀 **Scriptable 資料夾本身**，唔好揀入面子資料夾。狀態應由「未選擇」變成已授權；按「立即寫入 JSON」。
4. 同頁揀「Scriptable 主題」：預設、海藍、日落、森林、紫羅蘭或單色。主題寫落 JSON，只影響 Scriptable；原生 Widget 調色掣獨立。
5. 喺 Scriptable 新增 `i-widget` script，貼入 [`scriptable/i-widget.js`](../scriptable/i-widget.js) 全文；加入 Scriptable widget，`Script` 揀 `i-widget`。
6. Widget 編輯頁嘅 `Parameter` 用 `view=today`、`info`、`court`、`clock` 或 `accessory`。冇 parameter 時用 script 嘅 `previewView`（出廠 `today`）。鎖屏可用 Scriptable 行內／圓形／長方形。

正常資料路徑係 app 寫入，唔使先手放 JSON。手動 JSON 只適合進階診斷，唔可以當成 app bridge 驗收。詳細 view、schema、cache 同法院規則見 [`scriptable/README.md`](../scriptable/README.md)。

### 三件獨立事

- **app 寫入成功**：畫面顯示「已寫入，等待 iCloud 同步」，只證明 JSON 已 atomically 落入授權 folder。
- **iCloud 同步**：由 iCloud／File Provider 決定，app 冇提供同步完成通知。
- **Scriptable Widget 實際刷新**：要 Scriptable extension 真係執行並重新渲染；app 只直接 reload 原生 Overview／Info timeline，唔保證 Scriptable 何時更新。

原生 Overview／Info／Court timeline、`WidgetBackgroundRefresh.scheduleNext()` 同 Scriptable `refreshAfterDate` 嘅一般最早間隔統一為 **60 分鐘**；午夜／01:00、更份邊界同法院發布窗口仍會提前，10 分鐘 timeline entry 只係本地切換，唔使上網。背景返前景另有 **30 分鐘節流**：夠鐘先重新上網同重讀 Widget；30 分鐘內只用現有資料重排通知同同步 Live Activity。冷啟、deep link、手動更新同更份邊界保持即時；手動下拉先至繞過各來源 TTL。所有時間都**唔保證固定間隔**：iOS reload 預算、低耗電、背景限制、iCloud 下載同 extension 啟動時間都會影響實際結果。

### 更新間距記錄（2026-11-27）

| 項目 | 目前規則 |
| --- | --- |
| 法院非空案件表 | 沿用到下一個發布點；官方規律係前一個工作天約 18:30 公佈下一個聆訊日 |
| 法院空結果／失敗 | 18:30–19:00 空結果每 15 分鐘重試；19:00–20:00 空結果／失敗每 30 分鐘重試；20:00 後沿用到下一個發布點 |
| 法院 timeline／BGTask | 18:45 發布探測；空結果再短重試。18:30 entry 唔會假裝已切日，18:45 先請求新 timeline |
| Scriptable 法院 view | 跟香港時間，工作日 18:45:20 提早 reload；冇案件 19:00:20 再試，之後 30 分鐘 backoff；只重讀 JSON |
| 天氣 | 一般 60 分鐘；今日卡 10 分鐘成功快取去重，維持不變 |
| 天氣警告／港鐵 | 30 分鐘成功快取去重；警告超過 30 分鐘仍當過期 |
| 黃金 | 60 分鐘 TTL |
| 空氣質素 | 2 小時 TTL |
| 匯率 | 12 小時 TTL |
| 最新 iOS 版本 | 24 小時 TTL |
| VPS | 60 分鐘 TTL，對齊上游每小時輸出 |
| 學校日曆 | 6 小時 TTL |
| 更份 roster／basic／sheet／cards／places | 每次刷新試 roster；basic／sheet 6 小時、cards 12 小時、places 7 日，維持不變 |
| 公眾假期 | 7 日 TTL，維持不變 |
| 通知／Live Activity | 無獨立網絡 polling；絕對時間 trigger／系統倒數，維持不變 |

手動刷新（資料頁下拉、法院頁下拉、原生 Widget「即時更新」掣）繞過成功快取，但仍保留舊資料作離線 fallback；Widget 掣只喺 extension 容器留 5 分鐘 force flag，唔會令之後每次 timeline 都上網。法院同各來源 TTL 分開記錄：重新渲染、成功下載、重新匯出 JSON 唔係同一件事。

**剔除／擱置：** 今次 PR 只走 Xcode Build → iPhone + Scriptable 路線；ipa 功能仍擱置，`.github/workflows/ipa.yml` 只移除未審 PR 上 self-hosted runner 嘅入口，並限制 release 只能喺 main，唔改打包功能。Pyto／Python 診斷路徑唔處理。保留 `iWidgetExtension`、通知、AppIntents、交接提示同 Live Activity。

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

## 5b. 更份倒數（鎖定畫面 Live Activity）
鎖定畫面同動態島展開顯示「下一件事」（返工、接車、落地、放工）嘅倒數，加之後兩件事。資料同交接提示一樣（更份卡行程），但唔受「提前幾耐提」影響。動態島收窄時右邊顯示事件時刻，避免倒數迫到換行；展開或者鎖定畫面先睇倒數。

- **開法**：「設定」→「提示時間、語音、試聽」→「更份倒數」：
  - 「開 app 或者排提示時更新倒數」：開咗之後，開 app 同「排交接提示」執行時順手啟動／更新。
  - 「下一件事前幾耐開始顯示」：預設 3 小時前先出現；行緊嘅倒數如果下一件事已經超出呢個範圍，下一次更新會結束佢，入返範圍就重新開始。
  - 「而家開始／更新倒數」、「結束倒數」：手動測試（喺 app 前景，一定啟動得到）。
- **捷徑自動化**：新增兩個動作「更新更份倒數」、「結束更份倒數」。捷徑 App →「自動化」→「個人」→ 返工前幾個鐘，同之後每 2 小時左右 → 動作「更新更份倒數」→ 揀「立即執行」。
- **倒數點行**：鎖定畫面／動態島展開嘅倒數數字由系統自己跳，唔使不斷更新；但免費簽名冇 push，內容（下一件事係咩）只會喺開 app、捷徑執行時更新。
  倒數去到零之後會顯示「待更新」（唔會再列之後嘅事），直到下一次更新，所以自動化間隔唔好太疏。「之後」清單係上次同步嘅快照，唔識逐項自動消失；主事件到時後會整份標記待更新。
- **撳入 app**：撳鎖定畫面倒數會開啟「資料」頁並更新；即使關閉咗自動更新開關，只要仲有手動開始嘅倒數行緊，都會更新佢。
- **8 小時上限**：一個 Live Activity 最長行 8 小時（系統限制）；本 app 自己嘅門檻係 6 小時，行咗超過 6 小時，下一次更新會開新嘅再收返舊嘅。
- **要開權限**：iPhone 設定 → i-widget →「即時動態」。
- **未驗證（要喺真機試）**：免費簽名下 Live Activity 出唔出到；捷徑喺鎖機狀態下（背景）能否啟動；`待更新` 有冇自動轉。出事請話我知錯誤訊息。

## 真機驗收清單（尚未執行）

以下項目**未完成**；Node／XCTest／Python mock 測試唔可以當成已通過。每一項要由真機、真 iCloud、真 Scriptable extension 記錄結果。

### 1. 資料橋樑

- [ ] app 同 Scriptable 用同一個 iCloud 帳戶，Drive／Scriptable 開關已開；揀嘅係 **iCloud Drive／Scriptable 本身**。
- [ ] 用測試 build 將一個 schema 內可見、非敏感嘅欄位（例如 `duty.detailLines[0].value`，並用會顯示佢嘅 `today` 大尺寸 view）設成 **UUID A**；由 Swift app 真正啟動匯出，唔人手放 JSON。Scriptable app 預覽同 Home Screen widget 都讀到 A，而且冇「快取」標記。
- [ ] 將測試資料改成 **UUID B** 後重啟 app，確認 app 狀態顯示新一次成功寫入，Scriptable 其後讀到 B。
- [ ] 若重啟後仍讀 A，分開查三處：① bookmark 是否指向正確 folder、是否 device-only／失效而要重新授權；② iCloud 是否延遲或檔案仍係 A；③ Scriptable 是否顯示「快取」而 fallback 返 local last-good。唔好將三者混為一次失敗。

### 2. 離線快取

- [ ] 先連網成功讀取有效 iCloud JSON，令 Scriptable 寫好 local `i-widget-last-good.json`；確認畫面有資料。
- [ ] 保持有效 cache，開啟飛行模式，再次執行 Scriptable（app 預覽同 widget 分開確認）。資料仍顯示，保留原本 freshness 時間，並有「快取」標記；舊畫面靜止不動唔算 cache 測試成功。
- [ ] 恢復網絡，等 iCloud 下載最新 JSON，再確認 Scriptable 讀到最新資料、移除「快取」標記。

### 3. Widget 更新

- [ ] 記錄 app 寫入、iCloud 可見最新 JSON、Scriptable extension 執行、Home Screen 實際轉畫嘅時間；確認 widget 真係由 A 轉 B。
- [ ] 分開寫低三項結論：**「資料橋樑成立」**、**「離線快取成立」**、**「Widget 更新成立」**。第三項只證明真機曾更新，唔證明 `refreshAfterDate`／`earliestBeginDate` 會固定每 60 分鐘執行。

### 4. 原生功能不受橋接影響

- [ ] 移除 folder 授權或模擬 bridge 斷線／寫入失敗，確認 app 通知仍可排程／測試，AppIntents 仍可執行，已開啟嘅 `DutyLiveActivity` 仍可開始／更新。
- [ ] 確認 `iWidgetExtension` 保留，原生 Widget 同 Scriptable 可同時存在；冇新增 App Group 或 push entitlement。
- [ ] 真機結果未記錄前，文件同回報都唔可以寫「已完成驗收」。

## 測試指令

喺 repo 根目錄：

```sh
node scriptable/test-i-widget.js
python3 test_widget.py
python3 test_launcher.py
```

喺 `xcode/` 產生專案：

```sh
xcodegen generate
```

CI（`.github/workflows/ios.yml`）只喺 main push 或 review 後手動揀可信 branch／SHA 執行，PR 唔會自動喺 self-hosted runner 跑未審 code。`xcodebuild test` 使用相同嘅 simulator 指令：

```sh
UDID=$(xcrun simctl list devices available -j | python3 -c "
import json, sys
devices = json.load(sys.stdin)['devices']
for runtime, items in devices.items():
    if 'iOS' not in runtime:
        continue
    for item in items:
        if 'iPhone' in item['name']:
            print(item['udid']); sys.exit(0)
sys.exit('搵唔到 iPhone simulator')
")
xcodebuild test \
  -project iWidget.xcodeproj \
  -scheme iWidget \
  -destination "id=$UDID" \
  CODE_SIGNING_ALLOWED=NO
```

呢啲指令只覆蓋自動測試；真機清單仍要另做。

## 常見問題
- **免費 Apple ID 簽名 7 日有效**：過期後 app 開唔到，接機再 Run 一次就得。付費開發者帳號為一年。
- **Widget 搵唔到**：確認 `iWidget` app 已裝並開過一次；重啟 iPhone。
- **Scriptable 仍讀舊 A**：先分清 bookmark／folder、iCloud 延遲、local cache，再按上面真機清單排查。
- **改完 `project.yml`**：要重新 `xcodegen generate`。`.xcodeproj` 係產生出嚟嘅，唔使 commit。
- **跑單元測試**：Xcode 揀 scheme iWidget，按 ⌘U；CI（`.github/workflows/ios.yml`）都會自動跑。
