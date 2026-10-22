"""
i-widget SLOWDIAG v2 — 修正咗 v1 嘅致命 flaw。

v1 嘅問題
---------
`render()` 喺**最後**。如果 `exec(i_widget.py)` 令 process 被硬殺
（記憶體不足 / ObjC crash），render 永遠唔會行。
→ 下次 Reload 讀到 userkeys 有舊狀態，但又跑一次危險測試 → 又死。
→ **永遠都見唔到診斷結果。**

v2 嘅做法
---------
    讀 userkeys
      ├─ 有舊狀態 → **即刻顯示，然後 return，唔跑任何危險測試**
      └─ 冇舊狀態 → 逐步測試，每步寫入 userkeys，最後顯示

流程：
    Reload #1  → 跑測試，可能死（綠色）
    Reload #2  → 讀到上次死喺邊，即刻顯示（唔再測試）

⚠️ Reload #2 只會顯示，唔會再死。

診斷項目（逐步，每步寫入 userkeys）
--------------------------------
  A  Color.dynamic patch（Pyto 官方 bug）
  B  datetime
  C  os / getcwd
  D  os.statvfs          ← i_widget.py read_storage() 用
  E  _objc_class         ← i_widget.py read_battery()/read_system() 用
  F  UIDevice.batteryLevel
  G  wd.Spacer()         ← i_widget.py 用
  H  wd.SystemSymbol()   ← i_widget.py 用
  I  layout 方法（set_background_color / add_vertical_divider）
  J  下載真 i_widget.py
  K  compile
  L  exec  ← 死就係佢
  M  有冇叫 show_widget
"""

DIAG = "slowdiag-2.0"

import widgets as wd

KEY = "i_widget_slow_diag_v2"


# ------------------------------------------------------------------ userkeys
def _keys():
    try:
        import userkeys

        return userkeys
    except BaseException:
        return None


def _load():
    k = _keys()
    if k is None:
        return None
    try:
        raw = k.get(KEY)
    except BaseException:
        return None
    if not raw:
        return None
    try:
        value = eval(raw)
        return value if isinstance(value, list) else None
    except BaseException:
        return None


def _save(lines):
    k = _keys()
    if k is None:
        return
    try:
        k.set(repr(lines), KEY)          # Pyto API: set(value, key)
    except BaseException:
        pass


# ------------------------------------------------------------------ render
def render(lines):
    BG = wd.Color.rgb(0.08, 0.08, 0.09)
    FG = wd.Color.rgb(1, 1, 1)
    DIM = wd.Color.rgb(0.66, 0.66, 0.72)
    RED = wd.Color.rgb(1.0, 0.36, 0.30)
    GRN = wd.Color.rgb(0.35, 0.85, 0.45)

    w = wd.Widget()
    try:
        w.background_color = BG
    except BaseException:
        pass

    rows = [(f"{DIAG} — {len(lines)} 步", 9, FG)]
    rows.append(("", 6, DIM))
    for line in lines:
        color = DIM
        low = line.lower()
        if "死" in line or "⚠" in line or "fail" in low or "error" in low:
            color = RED
        elif line[:2] in ("✓ ", "OK"):
            color = GRN
        rows.append((line, 9, color))

    for name in ("small_layout", "medium_layout", "large_layout"):
        layout = getattr(w, name, None)
        if layout is None:
            continue
        try:
            layout.add_vertical_spacer()
        except BaseException:
            pass
        for text, size, color in rows:
            f = None
            try:
                f = wd.Font.system_font_of_size(size)
            except BaseException:
                pass
            node = None
            try:
                node = wd.Text(text, font=f, color=color)
            except BaseException:
                try:
                    node = wd.Text(text)
                except BaseException:
                    node = None
            if node is not None:
                try:
                    layout.add_row([node])
                except BaseException:
                    pass
        try:
            layout.add_vertical_spacer()
            layout.set_background_color(BG)
        except BaseException:
            pass

    try:
        from datetime import timedelta

        wd.schedule_next_reload(timedelta(minutes=30))
    except BaseException:
        pass
    wd.show_widget(w)


# ==========================================================================
# 分支一：有舊狀態 → 即刻顯示，唔跑任何危險測試
# ==========================================================================
PREVIOUS = _load()
if PREVIOUS:
    try:
        render(PREVIOUS)
    except BaseException as error:
        try:
            w2 = wd.Widget()
            w2.small_layout.add_row([wd.Text(f"render 死: {type(error).__name__}")])
            wd.show_widget(w2)
        except BaseException:
            pass
    # 刻意唔執行下面任何一行：呢個 run 淨係負責顯示。

else:
    # ======================================================================
    # 分支二：第一次行，逐步測試 + 寫入
    # ======================================================================
    L = []

    def mark(line):
        L.append(line)
        _save(L)                    # 立刻寫入，硬崩潰都唔會損失

    mark("A 開始（第一次 Reload）")

    # A: Color.dynamic patch
    try:
        def _patch():
            w1 = wd.Color.rgb(1, 1, 1)
            b1 = wd.Color.rgb(0, 0, 0)
            try:
                wd.Color.dynamic(light=w1, dark=b1)
                return "唔使 patch"
            except BaseException:
                pass
            from widgets import Color, __PyColor__

            Color.dynamic = staticmethod(lambda light, dark: Color(
                __PyColor__.colorWithLight(light.__py_color__, dark=dark.__py_color__)))
            return "已 patch"

        mark(f"A Color.dynamic {_patch()}")
    except BaseException as e:
        mark(f"A Color.dynamic 死 {type(e).__name__}")

    # B: datetime
    try:
        from datetime import datetime

        mark(f"B datetime OK {datetime.now():%H:%M:%S}")
    except BaseException as e:
        mark(f"B datetime 死 {type(e).__name__}")

    # C: os
    try:
        import os

        mark(f"C os OK cwd={os.getcwd()}"[:56])
    except BaseException as e:
        mark(f"C os 死 {type(e).__name__}")

    # D: statvfs（read_storage 用）
    try:
        import os

        _st = os.statvfs("/")
        mark(f"D statvfs OK free={_st.f_bavail * _st.f_frsize // 2**30}GB")
    except BaseException as e:
        mark(f"D statvfs 死 {type(e).__name__}: {e}"[:50])

    # E: _objc_class（read_battery / read_system 用）
    try:
        _objc_class("NSProcessInfo")
        mark("E _objc_class OK")
    except BaseException as e:
        mark(f"E _objc_class 死 {type(e).__name__}: {str(e)[:24]}")

    # F: UIDevice.batteryLevel
    try:
        _dev = _objc_class("UIDevice").currentDevice()
        mark(f"F battery OK level={_dev.batteryLevel}")
    except BaseException as e:
        mark(f"F battery 死 {type(e).__name__}: {str(e)[:24]}")

    # G: wd.Spacer()
    try:
        wd.Spacer()
        mark("G Spacer OK")
    except BaseException as e:
        mark(f"G Spacer 死 {type(e).__name__}")

    # H: wd.SystemSymbol()
    try:
        wd.SystemSymbol("internaldrive.fill")
        mark("H SystemSymbol OK")
    except BaseException as e:
        mark(f"H SystemSymbol 死 {type(e).__name__}")

    # I: layout 方法
    try:
        _w = wd.Widget()
        _l = _w.small_layout
        _l.add_vertical_spacer()
        _l.add_row([wd.Text("t")])
        _l.set_background_color(wd.Color.rgb(0, 0, 0))
        _l.add_vertical_divider()
        mark("I layout 全部方法 OK")
    except BaseException as e:
        mark(f"I layout 部分死 {type(e).__name__}: {str(e)[:22]}")

    # J: 下載真 i_widget.py
    code = None
    try:
        from urllib.request import Request, urlopen

        src = "https://raw.githubusercontent.com/iceninye/I-widget/main"
        code = urlopen(Request(f"{src}/i_widget.py",
                               headers={"User-Agent": "diag"}), timeout=10
                      ).read().decode("utf-8", "replace")
        mark(f"J 下載 OK {len(code)} bytes")
    except BaseException as e:
        mark(f"J 下載死 {type(e).__name__}: {str(e)[:24]}")

    # K: compile
    compiled = None
    if code:
        try:
            compiled = compile(code, "i_widget.py", "exec")
            mark("K compile OK")
        except BaseException as e:
            mark(f"K compile 死 {type(e).__name__}: {str(e)[:24]}")

    # L: exec（最危險，會硬殺 process）
    if compiled is not None:
        _real_show = wd.show_widget
        _calls = []
        try:
            wd.show_widget = lambda w=None: _calls.append(w)
        except BaseException:
            pass
        try:
            exec(compiled, {"__name__": "diag_probe", "__file__": "/tmp/i_widget.py"})
            mark(f"L exec 跑完，show_widget 叫咗 {len(_calls)} 次")
            if _calls:
                _rows = getattr(getattr(_calls[-1], "small_layout", None), "rows", None)
                mark(f"M widget rows={len(_rows) if _rows is not None else '?'}")
            else:
                mark("M ⚠️ i_widget.py 冇叫 show_widget")
        except BaseException as e:
            import traceback

            mark(f"L exec 死 {type(e).__name__}: {str(e)[:32]}")
            for _line in traceback.format_exc().strip().split("\n")[-3:]:
                L.append("   " + _line.strip()[:54])
                _save(L)
        finally:
            try:
                wd.show_widget = _real_show
            except BaseException:
                pass

    mark("Z 全部完成")
    try:
        render(L)
    except BaseException as error:
        try:
            w3 = wd.Widget()
            w3.small_layout.add_row([wd.Text(f"render 死: {type(error).__name__}")])
            wd.show_widget(w3)
        except BaseException:
            pass