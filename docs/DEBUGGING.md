# 真機診斷記錄：home screen 綠色 default template（2026-10-22）

## 症狀

Widget 放落 home screen 之後**只有綠色 default template，一個字都冇**。

```python
def main():
    now = datetime.now()
    level, charging = read_battery()      # ← 呢度死
    free, total = read_storage()          #    或者呢度
    system = read_system()                #    或者呢度

    widget = wd.Widget()
    build_small(widget.small_layout, ...)  # ← 或者呢度
    ...
    wd.schedule_next_reload(RELOAD_INTERVAL)
    wd.show_widget(widget)                 # ← 永遠執行唔到
```

## 點解綠色 = 診斷金鑰

**綠色 default template 嘅唯一成因，就係 `wd.show_widget()` 從來冇被叫過。**

`show_widget()` 係整個流程嘅最後一行。佢之前任何一步死掉（無論係 import
階段定係 `main()` 中途），iOS 都只會見到「Pyto 幫你畫嘅預設綠色」，
**唔會有任何錯誤訊息**。

所以診斷方向係唯一嘅：搵邊一步會死，而唔係「顏色／字體／排版」問題。

> 教訓：空白畫面零資訊量。冇錯誤畫面、冇版本標記嗰陣，排查完全靠盲猜。
> 呢個係後面加「版本標記」嘅直接原因。

## 真因：`__file__` 喺 Pyto Run Script 唔存在（module level NameError）

呢個係**最終真因**，喺 2026-10-22 經 `i_widget_safe.py` 二分定位先搵到。

```python
# i_widget_launcher.py（原本）
CACHE_DIR = os.path.dirname(os.path.abspath(__file__))   # ← module level
```

Pyto 嘅 **Run Script** widget 環境**唔定義 `__file__`**。所以：

```
module level  NameError: name '__file__' is not defined
     ↓
成個 module import 失敗
     ↓
main() 永遠冇執行 → show_widget() 從來冇被叫
     ↓
iOS 顯示綠色 default template
```

**點解之前搵唔到**：測試框架 `test_launcher.py` 自己都會傳 `"__file__": path`，
所以 53 個斷言全部通過，但真機一樣失敗 — **測試環境同真實環境唔同**。

### 實測證據

用 `no_file=True` 模擬真機環境，逐個情境測：

| 情境 | 修補前 | 修補後 |
| --- | --- | --- |
| A 有 `__file__` + 冇 userkeys | ✓ | ✓ |
| B **冇 `__file__`** | **✗ 綠色** | ✓ |
| C **冇 `__file__` + 有 userkeys** | **✗ 綠色** | ✓ |
| D 有 `__file__` + userkeys | ✓ | ✓ |

修補前 B/C 報 `NameError: name '__file__' is not defined`。

### 點解 `i_widget.py` 安全版冇事

`i_widget_safe.py` 完全冇用 `__file__`、冇上網、冇 userkeys — 所以跑得通。
**呢個正係二分法嘅價值**：safe 版成功就證明 `widgets` module 正常，
問題必然喺 launcher 專屬代碼。

### 修法

```python
def _cache_dir():
    try:
        return os.path.dirname(os.path.abspath(__file__))
    except NameError:
        pass
    for path in ("/tmp", os.path.expanduser("~"), os.getcwd()):
        try:
            if os.path.isdir(path):
                return path
        except BaseException:
            continue
    return "."
```

另一處 `exec(compiled, {"__file__": __file__})` 改用 `CACHED_PY`（已算出嘅路徑）。

### 測試盲區（重要）

`test_launcher.py` 嘅 `run_launcher()` 以前硬寫 `"__file__": path`，
**等於幫自己掩蓋咗真機嘅環境差異**。

修法：加 `no_file=True` 參數，模擬 Pyto Run Script。新增兩個情境：

- **【R】** 冇 `__file__` → 唔可以 NameError、唔可以綠色、layout 要有內容
- **【S】** 冇 `__file__` + 離線 + 快取已存在 → 仍然有畫面、零網絡請求

---

## 前置死因（`i_widget.py`，同一個症狀）

即使修好 `__file__`，`i_widget.py` 本身有三層 module-level 失敗風險，
修法詳見下面「解決方法」。兩者都會導致同一症狀（綠色），
所以排查時要同時考慮。

### 第 1 層：`_patch_color_dynamic()` 喺 module level 執行

```python
def _patch_color_dynamic():
    try:
        wd.Color.dynamic(light=..., dark=...)
        return                      # ← 冇 bug 就走
    except TypeError:               # ← 淨係捉 TypeError
        pass

    from widgets import Color, __PyColor__   # ← ImportError 會穿出去
    ...
    Color.dynamic = staticmethod(_dynamic)  # ← 賦值失敗會穿出去
```

三條路徑任何一條爆，都會令**成個 module import 失敗**：

1. `except TypeError` 太窄 — `Color.dynamic` 缺失、或任何其他內部錯誤都會穿出去
2. `from widgets import Color, __PyColor__` — `__PyColor__` 唔存在就 `ImportError`
3. `Color.dynamic = staticmethod(...)` — 賦值失敗（唯 frozen / 特殊實作）

### 第 2 層：`main()` 完全冇 try

`read_battery()` / `read_storage()` / `read_system()` 三個都依賴 iOS 專有 API：

```python
_objc_class("UIDevice")        # Objective-C runtime 反射
_objc_class("NSURL")           # 同上
_objc_class("NSProcessInfo")
os.statvfs(path)               # 檔案系統
```

任何一個喺某個 Pyto 版本、某次 reload、或權限限制下失敗 → `main()` 即死。

### 第 3 層：每個 family 綁在同一個命運

```python
build_small(widget.small_layout, ...)   # 爆 → large 都唔會畫
build_medium(...)
build_large(...)
build_large(widget.extra_large_layout, ...)  # extra_large_layout 可能唔存在
```

一個 family 爆，四個一齊冇。仲有 `wd.Spacer()`、`layout.set_background_color()`、
`layout.add_vertical_divider()`、`wd.SystemSymbol()` 呢啲額外 API 隨時可以失效。

## 為何之前的修補「冇效」

commit `8f6204d` 聲稱修好空白（launcher 加 try/except + 顯示錯誤訊息），
但只改咗 `PRIMARY` 一處色常數，`SECONDARY` / `GREEN` / `ORANGE` / `RED` /
`ACCENT` 同 launcher 錯誤畫面都仲係裸讀 `wd.COLOR_*`。

更關鍵：即使 launcher 成功捕捉到錯誤並叫 `_show_offline_widget()`，
**嗰個函式自己都裸讀 `wd.COLOR_SECONDARY_LABEL`** → 再死 → 綠色。

即係話：commit `8f6204d` 想解決嘅問題，佢自己嘅解決方法都解決唔到。

## 診斷過程中走過嘅弯路（記錄避免重複）

1. **第一個假設**：`wd.COLOR_SECONDARY_LABEL` 喺 Pyto `widgets` 唔存在
   → **錯**。用戶實測「舊版可以顯示」推翻了它。
2. **Mock 測試唔能夠回答真機問題**：`mock_pyto` 完全冇定義任何 `COLOR_*`，
   所以 (a) 測試通過唔代表真機通過，(b) 測試失敗亦唔代表真機失敗。
   用 mock 推論真機行為會得出相反結論。
3. **改用「唔猜，確保出到畫面」**：寫 `i_widget_safe.py`（只用最基本 API，
   對住刻意殘缺嘅 mock 測試通過）。用戶實機測試 → **正常顯示**。

`i_widget_safe.py` 成功呢件事本身就係關鍵證據：**`widgets` module 嘅
`Color.dynamic`、layout、`show_widget` 全部正常**。差異只喺 `i_widget.py`
用多咗 iOS 專有 API。

## 解決方法

### 1. `_patch_color_dynamic()` 每一層自己企穩

```python
try:
    _white = wd.Color.rgb(1.0, 1.0, 1.0)   # 連 rgb 都失敗就放棄 patch
    _black = wd.Color.rgb(0.0, 0.0, 0.0)
except BaseException:
    return

try:
    wd.Color.dynamic(light=_white, dark=_black)
    return
except BaseException:            # 擴闊：TypeError 唔夠
    pass

try:
    from widgets import Color, __PyColor__
    ...
except BaseException:            # ImportError 唔會再炸成個 module
    pass
```

### 2. `_dyn()` 安全 wrapper

```python
def _dyn(light, dark):
    return _safe(lambda: wd.Color.dynamic(light=light, dark=dark), dark)
```

`BACKGROUND` / `PRIMARY` 改用 `_dyn()`，dynamic 掛咗就退返深色色。

### 3. `main()` 每個資料源獨立保護

```python
level, charging = _safe(lambda: read_battery(), (None, False))
free, total     = _safe(lambda: read_storage(), (None, None))
system          = _safe(read_system, {})
```

寧願少一項資料，都唔好成個 widget 唔見。

### 4. 每個 family 獨立 try

```python
for name, builder in (("small_layout", ...), ("large_layout", ...)):
    layout = _safe(lambda n=name: getattr(widget, n))
    if layout is None:
        continue                       # extra_large_layout 可能唔存在
    try:
        builder(layout)
    except BaseException as error:
        _minimal_layout(layout, f"{name} 出錯", error, now)
```

### 5. `_minimal_layout()` 補底

出錯嘅 family 至少顯示時間 + 錯誤訊息，好過由 iOS 顯示綠色 template。

### 6. 模組級別 try

```python
try:
    main()
except BaseException as _fatal:
    ...
```

連 `main()` 本身爆都要出到畫面。

### 7. launcher 同樣加固

- `_load_code()` 包 try（之前完全冇保護）
- `main()` 外面包 `BaseException`
- `_show_offline_widget()` 加 `_try()` / `_text()` 防禦層，任何 font /
  color API 缺失都唔會炸
- 錯誤畫面顯示 `LAUNCHER_VERSION` + 遠端 fingerprint

## 設計原則（之後所有改動都要守）

> **任何一步失敗，都唔可以令畫面消失。**
> 寧願少一項資料、字體唔靚、顏色唔對，都唔好由 iOS 顯示綠色 template。

具體規則：

1. **module level 唔准用 `__file__`** — Pyto Run Script 唔定義，NameError = 全死
2. **module level 唔准直接讀 `wd.COLOR_*`** — 用 `getattr` + fallback
3. 每個資料源獨立 `try` — 一個失敗唔影響其他
4. 每個 widget family 獨立 `try` — small 壞唔影響 large
5. 每個可能不存在嘅 API 用 `getattr` 包住 + fallback
6. `module level` 嘅 code 必須自己企穩（佢一死就全死）
7. 最外層 `try` 一定 `show_widget()`，除非真係冇嘢可畫

## 測試環境必須模擬真機

`__file__` 呢個 bug 之所以躲咗咁耐，就係因為測試框架幫自己傳咗 `__file__`。

**規則：凡係真機同測試環境有差異嘅假設，都要喺測試加一個情境去驗證。**

`test_launcher.py` 現時有：
- `no_file=True` — 模擬 Pyto Run Script 冇 `__file__`
- 殘缺 mock — `wd.Spacer` / `wd.SystemSymbol` / `set_background_color` /
  `add_vertical_divider` / `__PyColor__` 全部缺失

## 驗證

對住**刻意殘缺**嘅 mock 測試（刻意刪走 `wd.Spacer`、`wd.SystemSymbol`、
`layout.set_background_color`、`layout.add_vertical_divider`、
`__PyColor__`，令 `Color.dynamic` throw）：

```
✅ show_widget 被叫 1 次
  small_layout         4 行
  medium_layout        4 行
  large_layout         4 行
  extra_large_layout   4 行
```

`test_launcher.py` 58/58 通過（含新增嘅 R/S 兩個情境）。

## 相關檔案

- `i_widget.py` — 正式 widget（四個 family 都有電量／儲存／開機時間／系統版本）
- `i_widget_safe.py` — 保證出到畫面嘅最小版本，用嚟二分定位問題
- `i_widget_launcher.py` — 自動更新 launcher
- `diagnose.py` — 診斷工具，列出真機有咩 `COLOR_*` / API
- `test_launcher.py` — 53 斷言
## ✅ 已確認真因：Pyto 官方 `Color.dynamic()` bug（2026-10-22 真機 probe 證實）

`i_widget_probe.py` 真機實測結果（一次過測 9 項，只叫一次 `show_widget`）：

| 步驟 | 結果 |
| --- | --- |
| 1 datetime | OK |
| 2 widgets API | 140 符號，`+SECONDARY_LABEL +GREEN +RED +Spacer +SystemSymbol` **全部存在** |
| **3 Color/Font/Text/dynamic** | **ERR TypeError: 'type' object is not iterable** |
| 4 Widget layout | 四個 family 全部 `+` |
| 5 userkeys | （probe 語法寫錯，真機 API 係 `.get()`/`.set()`，**冇問題**）|
| 6 `__file__` | **有** |
| 7 網絡 GitHub | OK，指紋 `3c5d06fecb2c` |
| 8 記憶體 | 可查 |
| 9 `exec` 字串 | OK |

只有第 3 項真係壞。查 Pyto 官方源碼（`ColdGrub1384/Pyto` → `Lib/widgets.py`）：

```python
@classmethod
def dynamic(cls, light: Color, dark: Color) -> Color:
    check(light, "light", Color)      # ← 傳 class，唔係 [class]
    check(dark,  "dark",  Color)
    return cls(__PyColor__.colorWithLight(
        light.__py_color__, dark=dark.__py_color__))
```

`from __check_type__ import check`，而 `check()` 內部做 `for t in expected:`。
傳入 `Color`（type object）就會：

```
TypeError: 'type' object is not iterable
```

**呢個係 Pyto 自己嘅 bug，唔係我哋代碼嘅問題。** 任何叫 `Color.dynamic()` 嘅代碼都會中招。

### 修法

繞過壞掉嘅 `check()`，自己實作：

```python
def _patch_color_dynamic():
    try:
        white = wd.Color.rgb(1.0, 1.0, 1.0)
        black = wd.Color.rgb(0.0, 0.0, 0.0)
    except BaseException:
        return
    try:
        wd.Color.dynamic(light=white, dark=black)
        return                      # 呢個 Pyto 版本冇 bug
    except BaseException:
        pass
    try:
        from widgets import Color, __PyColor__

        def _dynamic(light, dark):
            return Color(__PyColor__.colorWithLight(
                light.__py_color__, dark=dark.__py_color__))

        Color.dynamic = staticmethod(_dynamic)
    except BaseException:
        pass


def _dyn(light, dark):
    """安全版：patch 都唔成功就退返深色色。"""
    try:
        return wd.Color.dynamic(light=light, dark=dark)
    except BaseException:
        return dark
```

用 `verify_patch.py`（照抄 Pyto 官方 `check()` 行為）驗證：

```
未 patch：❌ TypeError: 'type' object is not iterable
patch 後：✅ 成功，light/dark 適應保留
```

**launcher 之前完全冇呢個 patch**（`i_widget.py` 有），所以每次離線都綠色。

## 診斷方法論教訓

1. **`show_widget()` 一個 script run 只理第一次** — 逐步更新畫面嘅診斷工具無效。
   必須收集齊結果，最後只叫一次。
2. **Mock 唔能夠重現真機 bug** — 用官方真實源碼重現先有效。
3. **推論係靠不住的** — 我連續猜錯 3 次（`COLOR_SECONDARY_LABEL` 唔存在、
   `__file__` 冇定義、`hashlib` C extension），全部被 probe 數據推翻。
   官方源碼 + 真機 probe 先係可靠證據。
4. **唔好淨係防禦，要搵官方 bug** — 見到 `TypeError: 'type' object is not iterable`
   就應該去搵邊個庫出錯，而唔係繼續加 try/except。

## ✅ 已確認真因（2026-10-22 slowdiag-2.0 真機 15 步）

`i_widget_slowdiag.py` 真機逐步寫入 userkeys（硬崩潰都捉得到），結果：

| 步驟 | 真機結果 |
| --- | --- |
| A | `Color.dynamic 唔使 patch` ← **Pyto 冇 bug，之前診斷錯** |
| B–D | `datetime` / `os` / `os.statvfs` 全部 OK（free=5GB） |
| **E–F** | **`_objc_class` → `NameError`（唔存在）**，`battery` 同樣死 |
| G–H | `wd.Spacer` / `wd.SystemSymbol` OK |
| I | layout 全部方法 OK |
| J–K | 下載 17043 bytes、`compile` OK |
| **L** | **`exec 跑完，show_widget 叫咗 1 次`** ← 🎯 |
| M | （我攔截咗 `show_widget`，查唔到） |

**L 行證明 `i_widget.py` 本身完全正常** —— 成功執行、成功調用 `show_widget()`。
所以死因一定喺 launcher 自己嘅流程。

## 設計缺陷：`load_code()` 完全冇驗證 + 30 分鐘節流

```python
# 舊版
def load_code():
    code = _keys_get(KEY_CODE)
    if code:                     # ← 讀到乜就返乜，零驗證
        return code
    return _read(CACHED_PY)

def _should_check():
    checked = load_checked()
    if not checked:
        return True
    return (time.time() - checked) >= CHECK_INTERVAL - CHECK_GRACE
```

兩個缺陷疊加，造成**永久鎖死**：

1. `load_code()` 唔驗證語法、唔檢查架構 → 一個舊壞版本就一直被攞返嚟 exec。
2. `_should_check()` 淨係睇時間 → 就算壞快取擺喺度，30 分鐘內都唔會去 GitHub。
   如果壞版本已經 `touch_checked()` 過 → **永遠唔會再檢查**。

結果：即使 `i_widget.py` 已經修好推上 GitHub，device 上面仍然行緊
`userkeys` 裡面嗰個舊版本 → 綠色 default template。

## 修法

### 1. 快取世代標記 `CACHE_MARKER`

```python
CACHE_MARKER = "I_WIDGET_API_2"

def _code_is_usable(code, source):
    """三重檢查：夠長 + 語法過 + 有 marker。"""
    try:
        if not code or len(code) < 200:
            return False
        compile(code, WIDGET_PY, "exec")
        if CACHE_MARKER not in code:      # ← 舊架構 → 丟棄
            _log(f"{source} 快取冇 {CACHE_MARKER} marker（舊版本），丟棄並重新落載")
            return False
        return True
    except SyntaxError:
        return False
    except Exception:
        return False
```

`i_widget.py` 加一行 `I_WIDGET_API_2 = True`。
**每次改 widget 結構就 bump marker → 所有舊快取自動失效，唔使用戶手動刪 widget。**

### 2. 快取不可信就一定要查

```python
def _should_check():
    if load_code() is None:
        return True          # 冇可信快取 → 必須即刻去攞，唔理時間
    checked = load_checked()
    ...
```

**節流只對「可信快取」生效。** 壞快取唔再有任何豁免權。

### 3. `_show_offline_widget` 死亡螺旋

```python
# 舊版：裸讀 4 個 layout，任何一個缺失就 AttributeError
for layout in (widget.small_layout, widget.medium_layout,
               widget.large_layout, widget.extra_large_layout):
```

跌入 `except` 之後**再裸讀** `small_layout` / `large_layout` → 再死 → 綠色。
即係「防禦層自己製造咗死鎖」。

改成 `getattr(..., None)` + 每個 `add_row` 都 `_try()` 包住；
`except` 分支重新起一個 `wd.Widget()`（原本嗰個未必綁定到）
並逐個 layout 試，成功就 `return`。

## 測試：T / U / V / W 四個情境（66/66 通過）

| 情境 | 鎖死嘅要求 |
| --- | --- |
| **T** | userkeys 冇 marker 嘅舊版本 → 必須丟棄並重新落載 |
| **U** | 檔案快取語法錯 → 必須丟棄並重新落載 |
| **V** | **節流窗口內** + 舊快取 → 照樣即刻重新落載（唔受 30 分鐘阻擋） |
| **W** | 有效快取 + 節流中 → 零網絡請求（防止反向 bug） |

V 同 W 係對照組：一個證明壞快取唔會被節流豁免，一個證明好快取唔會被
無謂打網絡。

### 測試本身嘅三個陷阱（我自己撞過）

1. **快取目錄係 launcher 檔案所在目錄**（`_cache_dir()` 行 159），
   唔係 `cache/` 子目錄。寫錯位置測試根本測唔到嘢（U 一開始就係咁）。
2. **`save()` 會將 `last_checked` 寫入 userkeys**，而 `load_checked()`
   讀 userkeys 優先於檔案 → 淨係改檔案唔會生效，兩邊都要改。
3. **唔可以再跑多一次 `run_launcher` 去「還原」快取** —— 嗰次會順手
   `touch_checked(now)`，節流窗口即刻失效（W 試咗幾次先發現）。

另外 `run_launcher()` 有 `reset_userkeys=True` 參數但**從來冇用過**，
所以「清 userkeys」要測試自己手動做。
