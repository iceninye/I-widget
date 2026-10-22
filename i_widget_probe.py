"""
i-widget PROBE — 一次過測完所有嘢，只叫一次 show_widget()。

上一版 i_widget_diag.py 教訓
---------------------------
佢每一步都叫 `wd.show_widget()`，但畫面停喺步驟 1。
即係 **Pyto 一個 script run 只會理第一次 `show_widget()`**，
之後嘅呼叫被忽略。

所以呢版：
  - 收集所有結果入一個 list
  - 最後**只叫一次** `show_widget()`
  - 一次過顯示全部 6 個步驟

如果呢版顯示齊 6 個步驟 → 冇任何嘢會死 → 問題喺 launcher 流程。
如果只顯示到第 N 步 → 就係嗰個嘢死咗（因為最後一次 show_widget 都冇到）。
"""

PROBE_VERSION = "probe-2.0"

import widgets as wd

RESULTS = []


def _try(fn, fallback=None):
    try:
        return fn()
    except BaseException as e:
        return f"ERR {type(e).__name__}: {str(e)[:40]}" if isinstance(fallback, str) else fallback


def probe(label, fn):
    """行一個測試，記低結果。永遠唔會拋出。"""
    try:
        value = fn()
        RESULTS.append((label, str(value)))
    except BaseException as error:
        RESULTS.append((label, f"ERR {type(error).__name__}: {str(error)[:40]}"))
    # 有 output 都立即 flush，方便喺 Pyto console 對數
    print(f"[probe] {label} = {RESULTS[-1][1][:60]}")


# --- 1. 時間 --------------------------------------------------------------
from datetime import datetime

_n = datetime.now()
probe("1 datetime", lambda: f"OK {_n:%H:%M:%S}")

# --- 2. widgets API 清單 --------------------------------------------------
def _api():
    names = dir(wd)
    marks = []
    for key in ("COLOR_SECONDARY_LABEL", "COLOR_SYSTEM_GREEN", "COLOR_SYSTEM_RED",
                "Color", "Font", "Text", "Spacer", "SystemSymbol", "Widget"):
        marks.append(("+" if key in names else "-") + key.replace("COLOR_", "").replace("SYSTEM_", ""))
    return f"{len(names)}符號 " + " ".join(marks)


probe("2 widgets API", _api)

# --- 3. Color / Font / Text 真實建構 -------------------------------------
def _build():
    c = wd.Color.rgb(1, 1, 1)
    f = wd.Font.system_font_of_size(12)
    t = wd.Text("x", font=f, color=c)
    d = wd.Color.dynamic(light=c, dark=c)
    return f"rgb/font/text/dynamic 全部 OK"


probe("3 建構 Color/Font/Text", _build)

# --- 4. Widget + layout 真實建構 -----------------------------------------
_W = None


def _layout():
    global _W
    _W = wd.Widget()
    names = []
    for n in ("small_layout", "medium_layout", "large_layout", "extra_large_layout"):
        lay = getattr(_W, n, None)
        if lay is None:
            names.append(f"-{n}")
            continue
        lay.add_row([wd.Text("probe")])
        try:
            lay.add_vertical_spacer()
            lay.set_background_color(wd.Color.rgb(0, 0, 0))
            names.append(f"+{n[:3]}")
        except BaseException as e:
            names.append(f"{n[:3]}半({type(e).__name__})")
    return " ".join(names)


probe("4 Widget layout", _layout)

# --- 5. userkeys ----------------------------------------------------------
def _uk():
    import userkeys

    try:
        userkeys["i_widget_probe_test"] = "ok"
        back = userkeys["i_widget_probe_test"]
        return f"OK 讀寫成功 ({back})"
    except BaseException as e:
        return f"import 到但操作失敗: {type(e).__name__}"


probe("5 userkeys", _uk)

# --- 6. __file__ ----------------------------------------------------------
probe("6 __file__", lambda: "有" if "__file__" in globals() else "冇")

# --- 7. 網絡 --------------------------------------------------------------
def _net():
    from urllib.request import Request, urlopen

    r = urlopen(Request(
        "https://raw.githubusercontent.com/iceninye/I-widget/main/i_widget.fingerprint",
        headers={"User-Agent": "probe"}), timeout=8)
    return f"OK 指紋 {r.read().decode('utf-8','replace').strip()[:12]}"


probe("7 網絡 GitHub", _net)

# --- 8. 記憶體 ------------------------------------------------------------
def _mem():
    import resource

    return f"{resource.getrusage(resource.RUSAGE_SELF).ru_maxrss // 1024} MB"


probe("8 記憶體", _mem)

# --- 9. 可否 exec 字串（launcher 必需）------------------------------------
def _exec():
    ns = {"v": 42}
    exec("out = v * 2", ns)
    return f"OK exec 正常 ({ns['out']})"


probe("9 exec 字串", _exec)


# ==========================================================================
# 唯一一次 show_widget()：上面 9 個步驟全部結果一次過顯示
# ==========================================================================
def _render():
    BG = _try(lambda: wd.Color.rgb(0.08, 0.08, 0.09))
    FG = _try(lambda: wd.Color.rgb(1, 1, 1))
    DIM = _try(lambda: wd.Color.rgb(0.60, 0.60, 0.64))
    RED = _try(lambda: wd.Color.rgb(1.0, 0.35, 0.30))

    w = wd.Widget()
    try:
        w.background_color = BG
    except BaseException:
        pass

    lines = [(f"probe {PROBE_VERSION}  {len(RESULTS)}/9", 9, DIM), ("=" * 4, 9, DIM)]
    for label, value in RESULTS:
        bad = value.startswith("ERR")
        lines.append((f"{label}:", 11, FG))
        lines.append((value, 9, RED if bad else DIM))

    for name in ("small_layout", "medium_layout", "large_layout", "extra_large_layout"):
        lay = getattr(w, name, None)
        if lay is None:
            continue
        _try(lay.add_vertical_spacer)
        for text, size, color in lines:
            f = _try(lambda s=size: wd.Font.system_font_of_size(s))
            kw = {"font": f} if f else {}
            if color is not None:
                kw["color"] = color
            node = _try(lambda t=text, k=kw: wd.Text(t, **k)) or _try(lambda t=text: wd.Text(t))
            if node is not None:
                _try(lambda n=node, L=lay: L.add_row([n]))
        _try(lay.add_vertical_spacer)
        _try(lambda L=lay: L.set_background_color(BG))

    _try(lambda: wd.schedule_next_reload(__import__("datetime").timedelta(minutes=30)))
    wd.show_widget(w)          # ← 唯一一次


try:
    _render()
except BaseException as error:
    print(f"[probe] render 失敗: {type(error).__name__}: {error}")
    try:
        w2 = wd.Widget()
        w2.small_layout.add_row([wd.Text(f"render 死: {type(error).__name__}")])
        wd.show_widget(w2)
    except BaseException:
        pass