# i-widget（Scriptable 版）

同 Pyto 版一樣嘅「時間／系統狀態」widget，但用 **Scriptable**（JavaScript）寫。

## 點解有呢個版本

Pyto 要喺 widget extension 入面行成個 CPython，記憶體上限好緊，而且排版工具得「一行行 + Spacer」。
Scriptable 用 JavaScript，引擎輕好多，亦有真正嘅 stack 排版、固定大小嘅 stack（可以畫真進度條）、
`Color.dynamic`、鎖屏 widget。

## 安裝

1. App Store 裝 **Scriptable**。
2. Scriptable 新增 script，將 [`i-widget.js`](i-widget.js) 成個貼入去（命名例如 `i-widget`）。
3. 長按 Home Screen → 加 **Scriptable** widget → 長按 → 編輯 Widget → `Script` 揀 `i-widget`。
4. 想加鎖屏 widget：鎖屏 → 自訂 → 加 Scriptable（圓形／長方形／行內）→ 揀 `i-widget`。

喺 Scriptable app 入面直接行，會預覽大尺寸（`CONFIG.previewFamily` 可改）。

## 顯示內容

| 尺寸 | 內容 |
| --- | --- |
| 小 | 星期（紅）＋日期、時間、電量 |
| 中 | 星期＋日期＋電量、大字時間、iOS 版本＋今日進度條 |
| 大 | 星期＋日期、置中大字時間、四張圓角卡：電量（進度條）、系統版本、螢幕亮度（進度條）、今日進度（進度條） |
| 鎖屏 行內／圓形／長方形 | 星期日期＋電量／電量圖示＋百分比／時間＋電量 |

時間用 `applyTimerStyle()`（由今日 00:00 起數）由 iOS 即時跳動，顯示 `h:mm:ss`，唔使 reload。
計時器喺 1 小時內只顯示「分:秒」，所以 00:00–00:59 用 `applyTimeStyle()`（靜態 `HH:MM`），並安排 00:00／01:00 前後 reload。

## 同 Pyto 版嘅差異（重要）

Scriptable 嘅 `Device` API **讀唔到**：

- 剩餘／總儲存空間
- 開機時間
- 低耗電模式

所以呢個版本冇呢三項。我用官方型別定義（`@types/scriptable-ios` 1.7.9）核對過：`Device` 只有
`batteryLevel()`、`isCharging()`、`isFullyCharged()`、`systemName()`、`systemVersion()`、`screenBrightness()` 等，
冇對應嘅 API。如果新版 Scriptable 加咗，改 `readDevice()` 同加一張 `card()` 就得。
作為補位，加咗**螢幕亮度**同**今日進度**（可喺 `CONFIG` 關閉）。

## 設定

`i-widget.js` 開頭嘅 `CONFIG`：`showBrightness`、`showDayProgress`、`reloadMinutes`、`previewFamily`。

## 測試

```bash
node scriptable/test-i-widget.js
```

用假 Scriptable 環境（`WidgetStack`、`WidgetDate`、`Device`…）執行，驗證各尺寸、計時器邊界、reload 時間、
讀唔到資料時唔 crash（46 項）。CI 會自動跑。

⚠️ **未喺真機試過。** API 用法係對住型別定義寫嘅；計時器樣式實際顯示（`1:30:15` 定 `01:30:15`）、
stack 實際對齊同間距要真機確認。Scriptable 嘅 widget 同樣受 iOS 嘅 reload 預算同低耗電模式限制，
`refreshAfterDate` 只係「唔早於」。

## 更新

目前要手動將新版 `i-widget.js` 貼入 Scriptable。需要自動跟 GitHub 更新嘅話，可以再加一個 loader
（`Request.loadString()` 下載、`FileManager` 快取），Pyto 版 launcher 嘅設計可以參考。
