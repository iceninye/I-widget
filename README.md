# i-widget

iPhone Home Screen 嘅「時間／系統狀態」widget，用 **Pyto**（iOS 上嘅 Python 環境）寫成。

唔需要 Mac、唔需要 Xcode，成個 widget 就係一隻 Python 檔案。

## 顯示內容

| 尺寸 | 內容 |
| --- | --- |
| 小 (2x2) | 大字時間、日期＋星期 |
| 中 (4x2) | 大字時間、日期＋星期、電量、可用儲存空間 |
| 大 (4x4) | 中尺寸全部內容，另加總儲存空間、開機時間、iOS 版本，低耗電模式開啟時多一行提示 |

時間用 `DynamicDate`（`DATE_STYLE_TIME`）交畀 iOS 自己更新，所以時鐘會自動跳動，唔需要頻繁 reload。其餘系統資訊每 15 分鐘重新讀取一次。

支援淺色／深色模式。

## 自動更新

Widget 會**自動跟 GitHub 最新版本**——改完 `i_widget.py` push 上 `main`，
手機下次 reload 就會自己攞新版，唔使再手動抄入 Pyto。

做法係「指紋檢查 + 本地快取 + 三層回退」：
widget 每次 reload 先問 GitHub 個極小嘅指紋檔有無變，變咗先落載完整程式碼；
下載完做語法檢查先寫入快取。任何一步失敗都繼續行舊快取，
所以網絡斷、GitHub 掛、推咗個壞 commit 落 `main`，widget 都唔會空白。

快取存喺 Pyto 官方 `userkeys`（`NSUserDefaults` suite，extension 同主 app 共用，
唔會被 iOS 清理），檔案只係後備。

設計理由同驗證見 [docs/AUTO-UPDATE.md](docs/AUTO-UPDATE.md)。

## 安裝

**用自動更新（建議）**

1. 喺 iPhone 裝 Pyto（App Store 搜尋「Pyto」，開發者 Emma Labbé）。
2. 將 **`i_widget_launcher.py`** 放入 Pyto 嘅 scripts 資料夾。
   唔使抄 `i_widget.py`——launcher 會自己落載。
3. 長按 Home Screen → 加**Pyto** widget → 揀尺寸 → 長按 widget → **編輯 Widget**：
   - `Widget Type`：`Run Script`
   - `Script`：揀 **`i_widget_launcher.py`**
4. 完成。第一次 reload 會落載（大約幾秒），之後自動跟最新版。

**本地執行（離線用）**

如果要完全離線、唔想佢上網，就直接用 `i_widget.py`：

1. 將 `i_widget.py` 放入 Pyto 嘅 scripts 資料夾。
2. 喺 Pyto 開 `i_widget.py` 行一次，確認冇紅字錯誤。
3. Widget 嘅 `Script` 揀 `i_widget.py`。

⚠️ 本地模式唔會自動更新，改咗 GitHub 都唔會生效。
兩種模式嘅檔案唔會互相影響，想轉換只需要改 widget 設定。

## 自訂

全部設定喺 `i_widget.py` 開頭同 `build_small`／`build_medium`／`build_large` 函數入面：

- `RELOAD_INTERVAL`：系統資訊更新頻率（預設 15 分鐘）。電量唔會即時反映，iOS 亦只會「唔早於」呢個時間更新。
- `BACKGROUND`、`PRIMARY`、`SECONDARY`、`GREEN`／`ORANGE`／`RED`：顏色。`wd.Color.dynamic(light=..., dark=...)` 分別設定淺色同深色模式。
- `build_small`／`build_medium`／`build_large`：版面。`layout.add_row([...])` 加一行，`wd.Spacer()` 撐開左右，`layout.add_vertical_spacer()` 撐開上下，`layout.add_vertical_divider()` 畫分隔線。
- `WEEKDAYS`：星期顯示文字。

## 已知限制

- **`wd.Color.dynamic()` 需要繞過 Pyto 嘅 bug**。Pyto 19.0（`widgets.py`）入面 `Color.dynamic()` 會叫 `check(light, "light", Color)`，但 `check()` 係 `for _type in types:` —— 傳入一個 type 而唔係 tuple，所以一定爆 `TypeError: 'type' object is not iterable`。呢個係官方 bug，唔係用法錯。程式頂部嘅 `_patch_color_dynamic()` 會先試一次，正常就唔理；爆 `TypeError` 就換用 `colorWithLight()` 直接砌返同樣效果。日後 Pyto 官方修咗，呢個 patch 會自動讓路唔會阻手。
- **電量有可能顯示 `—`**。widget 擴展（extension）嘅記憶體同權限都收得好緊，`UIDevice` 喺擴展入面經常讀唔到電量；程式已經自動退回用 IOKit 讀，若兩者都失敗就會顯示 `—`。想穩定讀到電量，可以開 Pyto 嘅 **「Start Handling Widgets In App」** 捷徑（Pyto 14+），令 widget script 改由 Pyto 主 app 執行，RAM 限制同權限都鬆好多；建議喺「捷徑」加自動化，每日行一次確保 Pyto 喺背景。
- **開機時間** 來自 `NSProcessInfo.systemUptime`，包含睡眠時間。
- **儲存空間** 用 `os.statvfs("/")`，數字同「設定 → 一般 → iPhone 儲存空間」未必完全一致。
- 「Run Script」模式嘅 script 唔可以 import 大部分含 C 擴展嘅套件（Pillow 除外），所以呢隻 widget 只用標準庫加 `rubicon.objc` 讀系統資訊。
- iOS 只會「唔早於」你要求嘅時間更新 widget，實際更新時間由系統決定。

## 檔案

| 檔案 | 角色 | 幾常改 |
| --- | --- | --- |
| `i_widget.py` | widget 本體 | 改版面／內容時 |
| `i_widget_launcher.py` | 自動更新啟動器，**widget 指向嘅係佢** | 幾乎唔使 |
| `i_widget.fingerprint` | 版本指紋（SHA256 前綴） | GitHub Action 自動生成 |
| `make_fingerprint.py` | 手動重算指紋 | 唔使 |
| `test_launcher.py` | 更新邏輯測試（10 種情境，34 項斷言） | 改 launcher 時 |
| `docs/AUTO-UPDATE.md` | 自更新設計文檔 | 唔使 |
| `LICENSE` | MIT | 唔使 |

因為 widget script 會被 Pyto 複製到 `Documents/<id>.py` 再執行，
`i_widget.py` 所有程式碼都刻意寫喺同一隻檔案入面，避免 import 鄰近模組時路徑出問題。

## 改程式碼之後

```bash
python3 make_fingerprint.py    # 重算指紋（正常唔使，Action 會自動做）
python3 test_launcher.py       # 34 項斷言，確認更新邏輯冇壞
git commit -am "..." && git push
```

Push 咗之後，GitHub Action 會自動更新 `i_widget.fingerprint`，
手機下次 reload 就會自己攞新版。

⚠️ 語法錯會被 launcher 擋（唔會炸 widget），但**語法啱、邏輯錯**嘅新版
會照樣執行。所以 push 前喺 Pyto 試一次。