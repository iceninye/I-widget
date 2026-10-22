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

## 真因：三層 module-level 未保護嘅失敗

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

1. 每個資料源獨立 `try` — 一個失敗唔影響其他
2. 每個 widget family 獨立 `try` — small 壞唔影響 large
3. 每個可能不存在嘅 API 用 `getattr` 包住 + fallback
4. `module level` 嘅 code 必須自己企穩（佢一死就全死）
5. 最外層 `try` 一定 `show_widget()`，除非真係冇嘢可畫

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

`test_launcher.py` 53/53 通過。

## 相關檔案

- `i_widget.py` — 正式 widget（四個 family 都有電量／儲存／開機時間／系統版本）
- `i_widget_safe.py` — 保證出到畫面嘅最小版本，用嚟二分定位問題
- `i_widget_launcher.py` — 自動更新 launcher
- `diagnose.py` — 診斷工具，列出真機有咩 `COLOR_*` / API
- `test_launcher.py` — 53 斷言