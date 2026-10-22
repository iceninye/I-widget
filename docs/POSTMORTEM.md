# Postmortem：i-widget 真機綠色 default template

**日期**：2026-10-22
**狀態**：已修好（launcher `1.6.0`，commit `2dc6510`）
**影響**：iOS home screen widget 長期只顯示綠色 default template，冇任何內容。

---

## 摘要（一段話）

`i_widget_launcher.py` 嘅快取邏輯有兩個缺陷：`load_code()` 讀到任何嘢就照用（零驗證），而 `_should_check()` 只看時間唔看快取質素。兩者疊加，令**一個壞快取可以永久鎖死個 widget**——launcher 永遠唔會再去 GitHub 攞新版，就算新版已經推上去。首個壞版本係 `8f6204d`（裸讀 `wd.COLOR_SECONDARY_LABEL`），之後我推咗 5 個修正版，你部機一次都冇攞到。

診斷過程中我連續猜錯 3 次，全部被真機 probe 推翻。真因係靠 `i_widget_slowdiag.py`（逐步寫入 userkeys）先搵到。

---

## 症狀

- Widget 位置顯示**綠色 default template**，冇字、冇圖。
- `i_widget_safe.py`（4.6 KB，單檔，唔上網、唔用 userkeys）**正常顯示**。
- `i_widget_launcher.py`（19 KB，自更新 launcher）**長期綠色**。
- 換任何 launcher 版本都冇用——重貼、改版本、清 widget 都冇用。

---

## 真因

### 缺陷 1：`load_code()` 完全冇驗證

```python
# 修正前
def load_code():
    """讀快取程式碼。userkeys → 檔案 → None。"""
    code = _keys_get(KEY_CODE)
    if code:                     # ← 讀到乜就返乜，零驗證
        return code
    return _read(CACHED_PY)
```

任何字串——語法錯、架構過時、API 用法已改——都會被當成有效程式碼交去 `exec()`。

### 缺陷 2：`_should_check()` 只看時間

```python
# 修正前
def _should_check():
    checked = load_checked()
    if not checked:
        return True
    return (time.time() - checked) >= CHECK_INTERVAL - CHECK_GRACE
```

`CHECK_INTERVAL = 30 * 60`。壞快取擺喺度，只要 30 分鐘內唔查，就唔會去 GitHub。

### 缺陷 3：`touch_checked()` 令情況永久化

`_try_update()` 遇到「已經係最新版」、「程式碼下載失敗」、「指紋格式唔啱」等情況，都會呼叫 `touch_checked(time.time())`。

**即係話：壞快取可以自己「打卡」話「我啱啱查過」，令自己獲得 30 分鐘豁免，連環續續，永遠唔會被檢查。**

### 三者疊加的效果

```
t0   push 8f6204d（壞版：裸讀 wd.COLOR_SECONDARY_LABEL）
     → launcher 落載、寫入 userkeys、touch_checked(now)
     → 執行 → AttributeError → 綠色

t0+30m  快取被判定「已經係最新版」→ touch_checked(now)
        （實際上係壞版，但指紋啱，所以判定為最新版）

t0+60m  重複...

我推咗 94551e8 / 32d4cdc / 7216551 / dafeb81 / 350d959 / 2dc6510
     → device 一次都冇重新落載，因為節流窗口從未失效
     → 一直行緊 8f6204d
```

**關鍵**：`8f6204d` 嘅指紋（`i_widget.fingerprint`）同我之後推嘅版本指紋**唔同**。如果 launcher 有正常檢查，`remote_fp == load_fingerprint()` 一定為 False，應該即刻落載新版。但節流令佢連指紋都冇去問。

---

## 修法

### 1. 快取世代標記（`CACHE_MARKER`）

```python
CACHE_MARKER = "I_WIDGET_API_2"

def _code_is_usable(code, source):
    """三重檢查：夠長 + 語法過 + 有 marker。"""
    try:
        if not code or len(code) < 200:
            _log(f"{source} 快取太短，丟棄")
            return False

        compile(code, WIDGET_PY, "exec")

        if CACHE_MARKER not in code:
            _log(f"{source} 快取冇 {CACHE_MARKER} marker（舊版本），丟棄並重新落載")
            return False

        return True
    except SyntaxError as error:
        _log(f"{source} 快取語法錯（{error}），丟棄")
        return False
    except Exception as error:
        _log(f"{source} 快取驗證失敗（{type(error).__name__}），丟棄")
        return False
```

`load_code()` 兩條路徑（userkeys、檔案）都要經過佢。

`i_widget.py` 加一行：

```python
# 快取世代標記：launcher 要求快取必須含有呢個 marker，
# 否則當作舊版本丟棄並重新落載（避免 outdated cache 鎖死 widget）。
I_WIDGET_API_2 = True
```

**點解唔淨係靠 `compile()`？**

因為 syntax 完全合法嘅舊版本一樣會令 widget 死。`8f6204d` 就係一個例子——`wd.COLOR_SECONDARY_LABEL` 語法完全合法，只係執行時 `AttributeError`。

**設計意義**：每次改 `i_widget.py` 嘅結構，就 bump marker。所有舊快取自動失效，**唔再需要用戶手動刪除 widget**。呢個係根治——之前每次修 bug 都要叫你「刪 widget → 重新加」，因為舊邏輯冇辦法自己察覺過時。

### 2. 節流只對可信快取生效

```python
def _should_check():
    """上次檢查過就唔好即刻再打網絡。

    ⚠️ 但有一個例外，而且係最重要嗰個：**快取唔可信就一定要查**。
    """
    if load_code() is None:
        return True          # 冇可信快取 → 必須即刻去攞，唔理時間
    checked = load_checked()
    if not checked:
        return True          # 冇記錄 = 即刻查一次
    return (time.time() - checked) >= CHECK_INTERVAL - CHECK_GRACE
```

壞快取冇任何豁免權。節流嘅原意（省電、省流量）完全保留——因為有效快取照樣受 `CHECK_INTERVAL` 保護。

### 3. `_show_offline_widget` 死亡螺旋

呢個係獨立但相關嘅缺陷：**防禦層自己製造咗死鎖**。

```python
# 修正前
for layout in (
    widget.small_layout,
    widget.medium_layout,
    widget.large_layout,
    widget.extra_large_layout,      # ← 如果呢個缺失
):                                   #    ↓
    layout.add_vertical_spacer()     # AttributeError
    ...
# → except:
try:
    widget = wd.Widget()
    for layout in (widget.small_layout, widget.large_layout):   # ← 再裸讀
        ...
except Exception:
    pass                             # ← 放棄 → 綠色
```

**最後防線自己會爆。** 修正：

```python
for layout in (
    getattr(widget, "small_layout", None),
    getattr(widget, "medium_layout", None),
    getattr(widget, "large_layout", None),
    getattr(widget, "extra_large_layout", None),
):
    if layout is None:
        continue
    _try(lambda: layout.add_vertical_spacer(), None)
    _try(lambda: layout.add_row([...]), None)
    ...
```

`except` 分支亦要**重新起一個 `wd.Widget()`**（原本嗰個未必綁定到），並逐個 layout 試，成功就 `return`。

---

## 測試

新增 **T / U / V / W** 四個情境，總計 **66/66 通過**。

| 情境 | 鎖死嘅要求 |
| --- | --- |
| **T** | userkeys 住緊冇 marker 嘅舊架構版本 → 必須丟棄並重新落載 |
| **U** | 檔案快取語法錯 → 必須丟棄並重新落載 |
| **V** | **節流窗口內** + 舊快取 → 照樣即刻重新落載（唔受 30 分鐘阻擋） |
| **W** | 有效快取 + 節流中 → 零網絡請求（防止反向 bug） |

V 同 W 係**對照組**：V 證明壞快取唔會被節流豁免，W 證明好快取唔會被無謂打網絡。缺任何一個都會漏咗一類 bug。

### 測試本身嘅陷阱（記低下次唔好再撞）

1. **快取目錄係 launcher 檔案所在目錄**（`_cache_dir()` 行 159），唔係 `cache/` 子目錄。寫錯位置嘅話測試根本測唔到嘢——U 情境一開始就係咁，全部斷言假通過。
2. **`save()` 會將 `last_checked` 寫入 userkeys**，而 `load_checked()` 讀 userkeys **優先於**檔案。淨係改檔案唔會生效，兩邊都要改。
3. **唔可以再跑多一次 `run_launcher` 去「還原」快取**——嗰次會順手 `touch_checked(now)`，節流窗口即刻失效，W 試咗幾次先發現。
4. `run_launcher()` 有 `reset_userkeys=True` 參數，但**函數內從來冇用過**。所以清 userkeys 要測試自己手動做。
5. R3 原本用「行數 ≥ 3」判斷係真 widget，但 fixture 每個 layout 只加 1 行。應該**睇文字內容**，唔係行數。

---

## 診斷方法論（呢部分最重要）

今次事故我浪費咗你大概 8 輪對話，全部係因為違反咗同一條規則。

### 1. 唔可以靠推論落判斷

我連續猜錯 3 次：

| 猜測 | 結果 | 被咩推翻 |
| --- | --- | --- |
| `wd.COLOR_SECONDARY_LABEL` 喺 Pyto 唔存在 | ❌ 錯 | 你舊版可以顯示；probe 實測 140 個 symbol 全部存在 |
| `__file__` 喺 Run Script 未定義 | ❌ 錯 | 修咗之後真機仍然綠色 |
| `hashlib` C extension 令 import 失敗 | ❌ 錯 | CPython 自動 fallback 純 Python |
| Pyto 官方 `Color.dynamic()` 有 bug | ❌ 錯 | slowdiag 真機：「唔使 patch」 |

**每次都係靠推理，冇真機數據。** 我違反咗自己嘅規矩。

### 2. Mock 唔能夠回答真機問題

`test_launcher.py` 53 個斷言全過，真機一樣失敗。原因係 mock 環境同真機差太遠：

- mock 有 `__file__`，真機冇（`run_launcher()` 自己傳咗 `__file__` = 幫自己掩蓋咗差異）
- mock 嘅 `Color.dynamic` 正常，真機可能唔同
- mock 無記憶體上限，真機有

**推論**：mock 只能驗證 Python 語法同 cache 分支邏輯，**唔能夠代表 WidgetKit extension 嘅 `show_widget()`、ObjC、sandbox、network 或 hard crash**。

### 3. `show_widget()` 一個 script run 只理第一次

我寫咗個逐步更新畫面嘅診斷工具（`i_widget_diag.py`），結果畫面停喺步驟 1。我一開始誤讀成「第一個 `show_widget()` 之後被忽略」，方向啱，但個工具設計錯——

**正確做法**：收集齊所有結果，最後**只叫一次** `show_widget()`。`i_widget_probe.py` 就係咁做，所以成功顯示 9 個步驟。

### 4. 硬崩潰捉唔到，必須逐步寫狀態

記憶體不足被系統殺、ObjC crash——呢類崩潰 `try/except` 完全捉唔到。一旦發生，連「顯示診斷」嗰段都唔會行。

`i_widget_launcher_diag.py` 就係咁死嘅（而且我仲自己整壞咗：monkeypatch 咗 `wd.Widget` 同 `wd.show_widget`，結果 `render()` 都用 fake 版，畫面完全冇嘢加）。

**正確做法**：**每做完一步就寫入 userkeys**。

```python
def mark(line):
    L.append(line)
    _save(L)                    # 立刻寫入，硬崩潰都唔會損失
```

而且要分成兩個分支：

```python
PREVIOUS = _load()
if PREVIOUS:
    render(PREVIOUS)            # 淨係顯示，唔再跑危險測試
else:
    ... 逐步測試 ...
```

否則 Reload 兩次都冇用——每次都會再死一次。呢個亦係我 v1 診斷工具嘅致命 flaw。

### 5. 對症狀嘅判斷

| 畫面 | 意思 |
| --- | --- |
| 完全冇嘢（純綠） | `show_widget()` 從來冇被叫 → process 死喺佢之前 |
| 有版本號但冇內容 | `show_widget()` 叫咗，但 layout 建構失敗 |
| 空白但有邊框 | layout 有，但所有 row 都加唔到 |

---

## 之後點做

1. Pyto 刪除舊 widget → 重新加 → 貼 `i_widget_launcher.py` 1.6.0
2. 第一次 reload 會因為 marker 唔匹配而強制重新落載新版 `i_widget.py`
3. 之後正常運作

**如果將來再改 `i_widget.py` 嘅結構，記得 bump `I_WIDGET_API_2`。**

---

## 相關檔案

| 檔案 | 用途 |
| --- | --- |
| `i_widget_launcher.py` | 自更新 launcher，`LAUNCHER_VERSION = "1.6.0"` |
| `i_widget.py` | widget 本體，含 `I_WIDGET_API_2 = True` marker |
| `i_widget_slowdiag.py` | 逐步寫 userkeys 嘅診斷工具（硬崩潰都捉得到） |
| `i_widget_probe.py` | 單次 `show_widget()` probe，9 項檢查 |
| `test_launcher.py` | 66 個斷言，T/U/V/W 鎖死「唔准用過期快取」 |
| `docs/DEBUGGING.md` | 診斷歷程記錄 |