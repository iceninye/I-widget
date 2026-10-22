"""
i-widget DIAGNOSTIC — 自報狀 launcher。

背景
----
`i_widget_safe.py`（4.6 KB）喺真機正常顯示，但 `i_widget_launcher.py`
（19 KB）長期只見綠色 default template。之前猜過兩個原因
（`COLOR_SECONDARY_LABEL` 唔存在、`__file__` 冇定義），都係錯。

與其繼續猜，呢個版本**開頭即刻畫一個畫面**，然後逐步做嘢，
每一步嘅結果都直接寫落畫面。咁你睇一眼就知道死喺邊一步。

無論死喺邊度（包括記憶體不足被系統殺），至少會見到第一個畫面。
"""

DIAG_VERSION = "diag-1.0"

import widgets as wd


def _try(fn, fallback=None):
    try:
        return fn()
    except BaseException:
        return fallback


def _rgb(r, g, b):
    return _try(lambda: wd.Color.rgb(r, g, b))


BG = _rgb(0.08, 0.08, 0.09)
FG = _rgb(1, 1, 1)
DIM = _rgb(0.62, 0.62, 0.66)


def _font(size):
    return _try(lambda: wd.Font.system_font_of_size(size))


def _show(lines, big=None):
    """畫一個畫面。任何一步失敗都要盡量畫到。"""
    try:
        w = wd.Widget()
    except BaseException:
        return False
    try:
        w.background_color = BG
    except BaseException:
        pass

    targets = []
    for name in ("small_layout", "medium_layout", "large_layout", "extra_large_layout"):
        lay = _try(lambda n=name: getattr(w, n, None))
        if lay is not None:
            targets.append(lay)

    for lay in targets:
        _try(lay.add_vertical_spacer)
        for value, size, color in lines:
            f = _font(size)
            kw = {}
            if f is not None:
                kw["font"] = f
            if color is not None:
                kw["color"] = color
            node = _try(lambda v=value, k=kw: wd.Text(v, **k))
            if node is None:
                node = _try(lambda v=value: wd.Text(v))
            if node is not None:
                _try(lambda n=node, L=lay: L.add_row([n]))
        _try(lay.add_vertical_spacer)
        _try(lambda L=lay: L.set_background_color(BG))

    try:
        from datetime import timedelta

        _try(lambda: wd.schedule_next_reload(timedelta(minutes=30)))
    except BaseException:
        pass
    try:
        wd.show_widget(w)
        return True
    except BaseException:
        return False


def _state(lines):
    _show([("i-widget diag " + DIAG_VERSION, 9, DIM)] + lines)


# --- 第一個畫面：萬一之後死咗，呢個一定睇到 -------------------------------
from datetime import datetime

_n = datetime.now()
_state([
    ("步驟 1: 基本畫面", 12, FG),
    (f"datetime OK {_n:%H:%M:%S}", 10, DIM),
])

# --- 步驟 2：可用 API 清單 -------------------------------------------------
try:
    import widgets

    names = sorted(n for n in dir(widgets) if not n.startswith("_"))
    has = {k: k in names for k in (
        "COLOR_SECONDARY_LABEL", "COLOR_SYSTEM_GREEN", "COLOR_SYSTEM_RED",
        "Color", "Font", "Text", "Spacer", "SystemSymbol", "Widget")}
    summary = " ".join(
        ("+" if has[k] else "-") + k.replace("COLOR_", "").replace("SYSTEM_", "")
        for k in ("COLOR_SECONDARY_LABEL", "COLOR_SYSTEM_GREEN", "Color", "Spacer"))
    _state([
        ("步驟 2: API 清單", 12, FG),
        (summary, 10, DIM),
        (f"共 {len(names)} 個符號", 9, DIM),
    ])
except BaseException as e:
    _state([("步驟 2 失敗", 12, FG), (f"{type(e).__name__}: {e}"[:90], 9, DIM)])

# --- 步驟 3：__file__ / os / 執行環境 --------------------------------------
try:
    has_file = "__file__" in dir()
except BaseException:
    has_file = False
try:
    import os

    cwd = os.getcwd()
except BaseException as e:
    cwd = f"失敗 {type(e).__name__}"
_state([
    ("步驟 3: 執行環境", 12, FG),
    (f"__file__ {'有' if has_file else '冇'}", 10, FG if has_file else DIM),
    (f"cwd {cwd}"[:60], 9, DIM),
])

# --- 步驟 4：userkeys ------------------------------------------------------
try:
    import userkeys

    keys = sorted(k for k in userkeys if str(k).startswith("i_widget"))
    uk = f"OK，{len(keys)} 個 i_widget key"
except BaseException as e:
    uk = f"{type(e).__name__}"
_state([("步驟 4: userkeys", 12, FG), (uk[:60], 10, DIM)])

# --- 步驟 5：網絡（真 GitHub）---------------------------------------------
try:
    from urllib.request import Request, urlopen

    r = urlopen(Request(
        "https://raw.githubusercontent.com/iceninye/I-widget/main/i_widget.fingerprint",
        headers={"User-Agent": "i-widget-diag"}), timeout=10)
    fp = r.read().decode("utf-8", "replace").strip()
    net = f"OK 指紋 {fp[:12]}"
except BaseException as e:
    net = f"{type(e).__name__}: {e}"[:60]
_state([("步驟 5: 網絡", 12, FG), (net, 10, DIM)])

# --- 步驟 6：記憶體實況 ----------------------------------------------------
try:
    import resource

    mem = f"{resource.getrusage(resource.RUSAGE_SELF).ru_maxrss // 1024} MB"
except BaseException as e:
    mem = f"查唔到 ({type(e).__name__})"
_state([("步驟 6: 記憶體", 12, FG), (mem, 10, DIM)])

# --- 最終畫面 --------------------------------------------------------------
_state([
    ("診斷完成", 13, FG),
    (f"{_n:%m-%d %H:%M:%S}", 10, DIM),
    ("步驟 1-6 已跑完", 9, DIM),
])