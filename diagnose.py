"""
i-widget 真機診斷 — 抄入 Pyto 做 widget，用完即刪。

用途：一次過顯示 Pyto `widgets` module 真實有咩 API，
      令「空白」呢個問題唔使再靠估。

用法
----
1. Pyto 加一個新 widget，Script 貼呢個檔案全部內容。
2. 放落 home screen，等一次 reload（或者 長按 → Reload / 移除再加入）。
3. 讀畫面上嘅三段：
     [1] 環境      — 有咩顏色常數 / 有冇 Color.dynamic
     [2] 執行狀態  — i_widget.py 有冇載入到
     [3] 快取狀態  — userkeys / 檔案 兩邊有咩

睇完之後把畫面內容講返俾我，然後就可以刪咗呢個 widget。

注意：呢個檔案唔會改動 repo 入面任何嘢，亦唔會上載。
"""

import sys
import traceback

import widgets as wd

# --- 逐個安全咁讀，缺一個都唔會炸 --------------------------
SAFE_COLORS = [
    "COLOR_LABEL",
    "COLOR_SECONDARY_LABEL",
    "COLOR_TERTIARY_LABEL",
    "COLOR_QUATERNARY_LABEL",
    "COLOR_SYSTEM_BACKGROUND",
    "COLOR_SECONDARY_SYSTEM_BACKGROUND",
    "COLOR_TERTIARY_SYSTEM_BACKGROUND",
    "COLOR_SYSTEM_FILL",
    "COLOR_SECONDARY_SYSTEM_FILL",
    "COLOR_TERTIARY_SYSTEM_FILL",
    "COLOR_SEPARATOR",
    "COLOR_OPAQUE_SEPARATOR",
    "COLOR_SYSTEM_RED",
    "COLOR_SYSTEM_ORANGE",
    "COLOR_SYSTEM_YELLOW",
    "COLOR_SYSTEM_GREEN",
    "COLOR_SYSTEM_BLUE",
    "COLOR_SYSTEM_INDIGO",
    "COLOR_SYSTEM_PURPLE",
    "COLOR_SYSTEM_PINK",
    "COLOR_SYSTEM_TEAL",
    "COLOR_SYSTEM_GRAY",
    "COLOR_RED",
    "COLOR_ORANGE",
    "COLOR_GREEN",
    "COLOR_BLUE",
    "COLOR_GRAY",
    "COLOR_WHITE",
    "COLOR_BLACK",
    "COLOR_CLEAR",
]

API_CHECKS = [
    ("Color.rgb", lambda: callable(getattr(wd.Color, "rgb", None))),
    ("Color.dynamic", lambda: callable(getattr(wd.Color, "dynamic", None))),
    ("Font.bold_system_font_of_size", lambda: callable(getattr(wd.Font, "bold_system_font_of_size", None))),
    ("Font.system_font_of_size", lambda: callable(getattr(wd.Font, "system_font_of_size", None))),
    ("show_widget", lambda: callable(getattr(wd, "show_widget", None))),
    ("schedule_next_reload", lambda: callable(getattr(wd, "schedule_next_reload", None))),
    ("userkeys", lambda: "userkeys" in dir() or "userkeys" in __builtins__ if isinstance(__builtins__, dict) else None),
    ("Widget.large_layout", lambda: hasattr(wd.Widget(), "large_layout")),
    ("extra_large_layout", lambda: hasattr(wd.Widget(), "extra_large_layout")),
    ("Text(color=)", lambda: "color" in str(getattr(wd, "Text", None) or "")),
]


def scan_colors():
    """回傳 (有, 冇) 兩組。"""
    present, missing = [], []
    for name in SAFE_COLORS:
        (present if hasattr(wd, name) else missing).append(name)
    return present, missing


def check_api():
    rows = []
    for label, probe in API_CHECKS:
        try:
            rows.append((label, probe()))
        except Exception as error:
            rows.append((label, f"ERR {type(error).__name__}"))
    return rows


def check_cache():
    """睇 userkeys 同檔案兩邊有咩。"""
    out = []
    try:
        import userkeys

        for key in ("i_widget_code", "i_widget_fingerprint", "i_widget_checked"):
            try:
                value = userkeys[str(key)]
                shown = f"{len(value)} chars" if isinstance(value, str) and len(value) > 40 else repr(value)[:40]
                out.append(f"{key} = {shown}")
            except Exception as error:
                out.append(f"{key} = <{type(error).__name__}>")
    except Exception as error:
        out.append(f"userkeys import 失敗: {type(error).__name__}")
    return out


def main():
    present, missing = scan_colors()

    env_lines = [
        f"Python {sys.version.split()[0]} · Pyto 冇 __version__",
        f"Color.dynamic 可用: {callable(getattr(wd.Color, 'dynamic', None))}",
        "",
        f"有 ({len(present)}): " + ", ".join(n.replace("COLOR_", "") for n in present[:14]),
    ]
    if missing:
        env_lines.append("")
        env_lines.append(f"冇 ({len(missing)}): " + ", ".join(n.replace("COLOR_", "") for n in missing))
        env_lines.append("")
        env_lines.append(">>> 上面「冇」清單入面任何一個，")
        env_lines.append(">>> 如果 i_widget.py 裸讀咗佢 = 就係空白真因")
    else:
        env_lines.append("")
        env_lines.append(">>> 全部常數都在，空白唔係色常數問題")

    api_lines = [f"{label} = {value}" for label, value in check_api()]
    cache_lines = check_cache() or ["（userkeys 完全讀唔到）"]

    widget = wd.Widget()
    for layout in (widget.small_layout, widget.medium_layout, widget.large_layout, widget.extra_large_layout):
        layout.add_vertical_spacer()

        layout.add_row([wd.Text("i-widget 診斷", font=wd.Font.bold_system_font_of_size(17))])

        layout.add_row([wd.Text("[1] 環境 / 色常數", font=wd.Font.bold_system_font_of_size(12))])
        for line in env_lines[:9]:
            layout.add_row([wd.Text(line, font=wd.Font.system_font_of_size(10))])

        layout.add_row([wd.Text("[2] API 檢查", font=wd.Font.bold_system_font_of_size(12))])
        for line in api_lines[:10]:
            layout.add_row([wd.Text(line, font=wd.Font.system_font_of_size(10))])

        layout.add_row([wd.Text("[3] 快取（userkeys）", font=wd.Font.bold_system_font_of_size(12))])
        for line in cache_lines[:4]:
            layout.add_row([wd.Text(line, font=wd.Font.system_font_of_size(10))])

        layout.add_vertical_spacer()

    wd.schedule_next_reload(__import__("datetime").timedelta(hours=6))
    wd.show_widget(widget)


try:
    main()
except Exception:
    # 連診斷都爆 → 至少令用戶見到 traceback
    try:
        widget = wd.Widget()
        for layout in (widget.small_layout, widget.large_layout):
            layout.add_vertical_spacer()
            layout.add_row([wd.Text("診斷失敗", font=wd.Font.bold_system_font_of_size(15))])
            for line in traceback.format_exc().splitlines()[-6:]:
                layout.add_row([wd.Text(line, font=wd.Font.system_font_of_size(9))])
            layout.add_vertical_spacer()
        wd.show_widget(widget)
    except Exception:
        pass