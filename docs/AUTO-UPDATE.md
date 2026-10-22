# 自更新方案

問題：`i_widget.py` 而家要人手抄入 Pyto，但 GitHub 上面先係最新版。
目標：widget 自動用 GitHub 上面最新版，唔使再手動搬。

## 三個選項的評估

### 選項 1：widget 每次直接執行 GitHub 版本

最簡單：每次 reload 都 `urlopen()` 拉 `i_widget.py`，再 `exec()`。

**問題：**

- **每次 reload 都拉一次完整程式碼。** widget 每 15 分鐘 reload，一日 96 次。
  `i_widget.py` 約 9 KB，一年 96 × 365 × 9 KB ≈ 315 MB，純粹為咗行同一份檔案。
- **慢。** WidgetKit 每次 reload 俾嘅時間有限，網絡往返要計入。
- **完全冇防護。** 網絡一斷就乜都出唔到，home screen 留白。
- **推壞 commit 即刻炸。** push 咗個 syntax error 落 `main`，
  下一次 reload 個 widget 就死，而且你未必即刻知。

### 選項 2：本地 script 只有一兩句 hyperlink

`i_widget.py` 改成一行 `exec(urlopen(GITHUB_RAW).read())`。

**比選項 1 好少少**（本地檔細啲），但**所有問題一樣存在**——
仲多一樣：debug 難。行到爛時你望住個本地檔只有一行，唔知佢做緊咩。

### 選項 3（建議）：指紋檢查 + 快取 + 三層回退 ✅

**我實作咗呢個。**

分兩層：

- `i_widget.py` —— widget 本體。**唔需要改。** 想更新就改呢個檔、push。
- `i_widget_launcher.py` —— widget 實際指向嘅檔案。細、快、穩定，
  除非改更新策略本身，否則唔使再碰。

Launcher 每次 reload 嘅流程：

```
1. 睇下 10 分鐘內有冇查過（用快取檔 mtime 節流）
2. 冇 → 拉 i_widget.fingerprint（一行，約 40 bytes）
3. 同本地指紋一樣？ → 完全唔落載，直接行快取
4. 唔一樣 → 拉完整 i_widget.py
5. compile() 語法檢查
     錯 → 棄置新版本，繼續行舊快取，指紋唔更新（下次再試）
     對 → 寫入快取，更新指紋
6. 行快取
```

三層回退，確保**任何情況下 widget 都唔會空白或崩潰**：

| 情況 | 結果 |
|---|---|
| 遠端有新好版本 | 落載 → 快取 → 執行新版 |
| 遠端冇變 | 零網絡用量（指紋相同就唔落載） |
| 網絡斷／GitHub 掛咗／限流 | 靜靜行本地快取，畫面正常 |
| 推咗個 syntax error 上 main | **拒絕該版本**，繼續行舊快取，下次再試 |
| 404（檔案俾人刪咗） | 行快取；冇快取就顯示「更新失敗」 |
| 首次安裝 + 網絡斷 | 顯示一個講明「更新失敗」嘅 widget，唔會留白 |

## 為咗咁設計

**點解唔每次都落載？**
Extension 有 RAM 上限，WidgetKit 每次 reload 俾嘅時間亦有限。
用指紋先問「變咗未」，把網絡用量由每日 96 次完整下載降到近乎零。

**點解要語法檢查？**
`compile()` 好平（唔執行），但擋得住 syntax error。
一個壞 commit 唔應該有能力炸你個 home screen——呢個係整個設計嘅重點。

**點解指紋唔會更新（喺壞版本情況）？**
因為壞版本要「下次再試」。如果照更新指紋，launcher 就會永遠以為
自己已經最新，唔會再問 GitHub 要修好咗嘅版本。留住舊指紋 = 自動重試。

**點解用 SHA256 而唔係 commit SHA？**
Device 只需要知道「變咗未」，唔需要知道係邊個 commit 改嘅。
用內容 hash，`make_fingerprint.py` 唔使執行 git。

## Fingerprint 邊個嚟？

由 `.github/workflows/fingerprint.yml` 自動生成：每次 push 咗
`i_widget.py` 去 `main`，Action 會重算 SHA256、commit、push 返。

**唔需要手動做嘢。** 如果改壞咗 `i_widget.py`（例如刪走 fingerprint 檔），
手動跑：

```bash
python3 make_fingerprint.py
```

然後連 `i_widget.fingerprint` 一起 commit。

⚠️ **只有 `i_widget.py` 改先會觸發。** 改 `i_widget_launcher.py` 唔使重算——
launcher 唔參與指紋（佢係本地檔，從來唔會被遠端取代）。

## 檔案角色

| 檔案 | 角色 | 幾常改 |
|---|---|---|
| `i_widget.py` | widget 本體 | 改版面／內容時 |
| `i_widget_launcher.py` | **widget 指向嘅檔案** | 幾乎唔使 |
| `i_widget.fingerprint` | 版本指紋 | GitHub Action 自動 |
| `make_fingerprint.py` | 手動重算指紋 | 唔使 |
| `i_widget.cached.py` | device 本地快取（device 產生，唔入 repo） | 自動 |

## 安裝

Widget 要指向 **`i_widget_launcher.py`**，唔再係 `i_widget.py`。

1. 抄 `i_widget_launcher.py` 入 Pyto scripts 資料夾。
   （唔使抄 `i_widget.py`——launcher 會自己落載。）
2. 長按 widget → 編輯 Widget → `Script` 揀 **`i_widget_launcher.py`**。
3. 第一次 reload 會落載並建立快取，大約幾秒。

確認 log（Pyto console 或 XCUITest 輸出）：

```
[i-widget] 發現新版 5e93688f50bf6370，落載中
[i-widget] 已更新到本地快取
[i-widget] 執行中（來源：cache）
```

之後每次 reload：

```
[i-widget] 已經係最新版
[i-widget] 執行中（來源：cache）
```

## 驗證

`test_launcher.py` 用本地 HTTP server 扮 GitHub，跑齊 7 種情境共 18 項
斷言，全部通過——包括「推壞版本被拒絕」「網絡死仍出畫面」「404 唔 crash」
「首次安裝離線顯示提示」。

```bash
python3 test_launcher.py
```

⚠️ **Mock 唔等於真機。** 測試證明嘅係邏輯正確（更新、拒絕、回退），
唔係證明 iOS extension 真係畀到 network + 檔案寫入權限。
真機確認：裝完 launcher 後，查 home screen 有冇正常出時間
（出到 = 網絡同檔案都 work）。

## 已知限制

- **唔會自動回滾。** 語法錯會被擋，但「語法啱、邏輯錯」嘅新版會照樣執行。
  要保護呢種情況，需要真機測試先 push 落 `main`。
- **指紋更新靠 Action。** 如果 Actions 被停用或者 repo 設定唔到，
  fingerprint 唔會更新，launcher 會永遠行第一次落載嘅版本。
  改壞咗就手動跑 `make_fingerprint.py`。
- **每次 reload 都係本機讀檔。** 快取存在 `i_widget_launcher.py` 同一個目錄。
  如果 iOS 清理 Pyto 嘅 temp 空間，快取會冇，launcher 下次重新落載（正常）。
- **安全性**：呢個做法會執行網絡上下載嚟嘅 code。等同「你信任嗰個 repo」。
  repo 係你自己嘅所以冇問題，但如果將來 fork 咗或者用別人嘅 raw URL，
  要諗清楚。