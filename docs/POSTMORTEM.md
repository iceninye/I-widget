# Postmortem：Home screen 長期綠色 default template

**日期**：2026-10-22
**狀態**：已修好並經真機確認（widget 正常顯示）
**影響**：放落 home screen 嘅 widget 長期只顯示 Pyto 預設綠色底，冇任何內容。喺 Pyto app 入面行同一隻 script 就正常。

---

## 一段話

`i_widget.py` 砌版面時叫 `wd.DynamicDate(now, style=TIME, font=…, color=PRIMARY)`，
喺 widget extension 入面**令 process 被直接殺死**——冇 Python 例外、冇錯誤訊息。
`show_widget()` 因此從來冇被叫到，iOS 顯示預設綠色。
`try/except` 對「process 被殺」完全冇用，所以之前加咗幾層防禦都冇效。

最後係靠**喺真 launcher 入面逐步寫足跡到 userkeys** 先搵到：兩個獨立 process 都停喺同一行 `建 clock`。
最可能嘅兇手係 `color=PRIMARY`（自訂動態色）；只帶 `font` 嘅寫法 `clock_font` 真機運作正常。
（`color` 唔係單獨隔離驗證過：第一個寫法成功後，鏈就停咗。）

---

## 判斷依據（真機數據）

| 證據 | 結論 |
| --- | --- |
| `i_widget_safe.py`（只用 `Text`）正常顯示 | `widgets` 模組、`show_widget`、extension 環境都冇事 |
| `i_widget_trace.py` 砌出嘅 widget 正常顯示 | 同一個 Pyto 環境入面 `show_widget` 可用 |
| 足跡：電量 0.5、儲存 32/255 GB、系統資料全部讀到 | ObjC／ctypes 讀取冇問題 |
| 足跡：`建 spacer`、`建 spacer`、`建 clock` 之後**完**，兩個 process（p982、p985）一樣 | 死喺 `DynamicDate` 附近 |
| `i_widget.inflight` 殘留 `clock|…` | 標記冇被清走 = process 喺建 clock 期間死 |
| launcher 無 `8 exec 完` | exec 從來冇返回 = 被殺／卡死，唔係例外 |
| 改為 `clock_font`（無 `color`）後四個尺寸跑到 `show_widget 已叫` | 修復 |

## 次要問題（真實，但唔係主因）

1. **壞快取 + 30 分鐘節流**：`load_code()` 讀到乜就用乜，`_should_check()` 只睇時間，
   所以一個壞快取可以令 launcher 唔去 GitHub。已修（快取要過 marker 驗證；快取唔可信就一定檢查）。
   呢個令修正版遲遲落載唔到，**拖長咗診斷時間**，但就算冇呢個問題，`DynamicDate` 一樣會死。
2. **刪 widget 唔會清 userkeys**：快取同檢查時間都留喺 `group.pyto`，所以「刪咗再加」冇用。
3. **推理式診斷**：早期報告列咗幾個「真因」（`COLOR_SECONDARY_LABEL` 唔存在、`__file__` 冇定義、
   `hashlib`、`Color.dynamic` 有 bug），後來全部被真機數據推翻，或者從來冇被量度過。
   `__file__` 嗰個亦已改為安全寫法，但唔係今次綠色嘅原因。

## 點解之前搵唔到

- **`try/except` 捉唔到 process 被殺。** 呢類死亡（native 崩潰、記憶體／時限）冇 Python 層面嘅痕跡。
- **Mock 測試通過唔代表真機通過。** `test_launcher.py` 嘅 mock 有 `__file__`、冇記憶體上限、
  `DynamicDate` 永遠成功；所以幾十項斷言全過，真機照死。
- **診斷工具同真貨唔同。** `slowdiag`／`diag` 版本都係另一隻 script，跑得通唔代表真 launcher 跑得通。
  最後有效嘅做法，係直接喺**真 launcher 同真 widget** 入面寫足跡。
- **同時有幾個 process。** iOS 為不同尺寸同時跑多個 process，佢哋共用同一個 userkeys，
  足跡會互相覆寫，所以單一份足跡斷尾唔等於死咗。

## 修法

### 1. 足跡（`i_widget.trace`、`i_widget.trace2`）
launcher 同 widget 本體每過一個關卡就寫一行到 userkeys，附 pid，保留最後 40 行。
用 `i_widget_trace.py` 讀出。

### 2. 崩潰自癒（`i_widget.py`）
建立有風險元件（`DynamicDate`／`SystemSymbol`／`Spacer`／divider／background）之前，
先寫 `inflight = 名|時間`；建完先清。Process 死咗標記就留低。
下次 reload 見到超過 10 秒前嘅標記：

- 記一次 strike；**同一個元件連續死兩次先停用**（多個 process 同時死會互相覆寫標記，單次證據可能係誤判——今次 `spacer` 就係咁被誤停用）。
- 停用後用後備：時間改試下一種 `DynamicDate` 寫法，全部死晒就用靜態文字；圖示／Spacer 等直接略過。
- 順利完成一輪就清零 strike，所以只計「連續」。
- `BAN_EPOCH` 版本號：元件寫法改動或發現誤判時 +1，每部機第一次行新版會自動清走舊停用名單，唔使手動 `userkeys.set`。

### 3. 時間元件
`clock()` 依次試：只帶 font → 只帶 color → 全部預設 → 靜態文字。「font+color」寫法已確認致命，唔再試。

---

## 日後遇到「綠色」點查

1. 喺 Pyto 行 `i_widget_trace.py`，睇最後一行：
   - 去到 `show_widget 已叫` → 畫面內容有問題（睇 `banned`），唔係崩潰。
   - 停喺某個 `建 X` → X 就係兇手；`inflight` 會寫住佢。連死兩次會自動停用，widget 自己恢復。
   - 停喺 `7 即將 exec` 之前 → launcher 或快取問題。
2. 用 `i_widget_safe.py` 二分：safe 正常、正式版綠色 → 正式版某個元件。
3. `i_widget.banned` 有嘢而你覺得係誤判 → 將 `BAN_EPOCH` +1 push 上去，或者
   `userkeys.set("", "i_widget.banned")`。
4. 想即刻落載新版而唔等 30 分鐘：`userkeys.set(1.0, "i_widget.last_checked")`。

## 教訓

1. **綠色 = 冇人叫到 `show_widget`，原因可以係例外，亦可以係 process 被殺。** 只有足跡分辨到。
2. **唔好用推理落判斷。** 呢次報告頭幾個「真因」全部係推理；最後靠真機數據先搵到。
3. **喺真貨入面量度**，唔好另外寫一隻診斷 script。
4. **有風險嘅 native 元件要有 in-flight 標記**，死過就自動繞開，唔好靠人手逐個試。
5. **多 process 共用狀態**，單次觀察唔夠證據：要求連續兩次先作決定。

## 相關檔案

| 檔案 | 用途 |
| --- | --- |
| `i_widget.py` | widget 本體，含足跡、崩潰自癒、`BAN_EPOCH` |
| `i_widget_launcher.py` | 自更新 launcher，含足跡 |
| `i_widget_trace.py` | 讀出足跡同停用名單（console＋widget） |
| `i_widget_safe.py` | 保證出到畫面嘅最小版本，二分用 |
| `test_widget.py` | smoke test＋崩潰自癒情境 R |
| `test_launcher.py` | 更新邏輯測試 |
