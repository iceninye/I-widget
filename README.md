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

## 安裝

1. 喺 iPhone 裝 Pyto（App Store 搜尋「Pyto」，開發者 Emma Labbé）。
2. 將 `i_widget.py` 放入 Pyto 嘅 scripts 資料夾：喺「檔案」App 搵到 `Pyto` 呢個位置，將檔案複製入去；亦可以喺 Pyto 入面新建檔案再貼上內容。
3. 喺 Pyto 開 `i_widget.py` 行一次，確認冇紅字錯誤。
4. 長按 Home Screen → 加**Pyto** widget → 揀尺寸 → 長按 widget → **編輯 Widget**：
   - `Widget Type`：`Run Script`
   - `Script`：揀 `i_widget.py`
5. 完成。想換尺寸就另外加一個 widget 再揀。

## 自訂

全部設定喺 `i_widget.py` 開頭同 `build_small`／`build_medium`／`build_large` 函數入面：

- `RELOAD_INTERVAL`：系統資訊更新頻率（預設 15 分鐘）。電量唔會即時反映，iOS 亦只會「唔早於」呢個時間更新。
- `BACKGROUND`、`PRIMARY`、`SECONDARY`、`GREEN`／`ORANGE`／`RED`：顏色。`wd.Color.dynamic(light=..., dark=...)` 分別設定淺色同深色模式。
- `build_small`／`build_medium`／`build_large`：版面。`layout.add_row([...])` 加一行，`wd.Spacer()` 撐開左右，`layout.add_vertical_spacer()` 撐開上下，`layout.add_vertical_divider()` 畫分隔線。
- `WEEKDAYS`：星期顯示文字。

## 已知限制

- **電量有可能顯示 `—`**。widget 擴展（extension）嘅記憶體同權限都收得好緊，`UIDevice` 喺擴展入面經常讀唔到電量；程式已經自動退回用 IOKit 讀，若兩者都失敗就會顯示 `—`。想穩定讀到電量，可以開 Pyto 嘅 **「Start Handling Widgets In App」** 捷徑（Pyto 14+），令 widget script 改由 Pyto 主 app 執行，RAM 限制同權限都鬆好多；建議喺「捷徑」加自動化，每日行一次確保 Pyto 喺背景。
- **開機時間** 來自 `NSProcessInfo.systemUptime`，包含睡眠時間。
- **儲存空間** 用 `os.statvfs("/")`，數字同「設定 → 一般 → iPhone 儲存空間」未必完全一致。
- 「Run Script」模式嘅 script 唔可以 import 大部分含 C 擴展嘅套件（Pillow 除外），所以呢隻 widget 只用標準庫加 `rubicon.objc` 讀系統資訊。
- iOS 只會「唔早於」你要求嘅時間更新 widget，實際更新時間由系統決定。

## 檔案

```
i_widget.py   主程式（widget 本身）
LICENSE       MIT
```

因為 widget script 會被 Pyto 複製到 `Documents/<id>.py` 再執行，所有程式碼都刻意寫喺同一隻檔案入面，避免 import 鄰近模組時路徑出問題。