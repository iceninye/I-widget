"""i_widget.py 嘅 smoke test：用 mock Pyto 跑一次，確認四個尺寸都砌得出。

Linux／macOS 上面冇 rubicon，所以電量、iOS 版本會走「讀唔到」嘅路徑 ——
正好測埋 widget 喺 extension 讀唔到資料時都唔會 crash。
"""
import os
import sys
from datetime import datetime, timedelta

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import mock_pyto  # noqa: E402,F401  import 時會註冊假 widgets / userkeys
from mock_pyto import RELOADS, SHOWN, Text, text_of  # noqa: E402

PASS, FAIL = [], []


def check(name, cond, detail=""):
    (PASS if cond else FAIL).append(name)
    print(f"  {'✓' if cond else '✗ FAIL'}  {name}{('  → ' + detail) if detail and not cond else ''}")


def texts(layout):
    return [text_of(c) for row in layout.rows if isinstance(row, list)
            for c in row if isinstance(c, Text)]


path = os.path.join(HERE, "i_widget.py")
g = {"__name__": "__main__", "__file__": path}
SHOWN.clear(); RELOADS.clear()

print("\n【W】執行 i_widget.py")
try:
    exec(compile(open(path, encoding="utf-8").read(), path, "exec"), g)
    err = None
except Exception as e:  # pragma: no cover - 失敗會喺下面報
    err = e
check("W1 冇 crash", err is None, f"{type(err).__name__}: {err}" if err else "")
check("W2 show_widget 叫咗一次", len(SHOWN) == 1, f"{SHOWN}")
check("W3 reload 30 分鐘", RELOADS == [timedelta(minutes=30)], f"{RELOADS}")

if SHOWN:
    w = SHOWN[0]
    weekday = g["WEEKDAYS"][datetime.now().weekday()]
    for name in ("small_layout", "medium_layout", "large_layout", "extra_large_layout"):
        layout = getattr(w, name)
        check(f"W4 {name} 有內容同背景", bool(layout.rows) and layout.background is not None)
        check(f"W5 {name} 有星期", weekday in texts(layout), f"{texts(layout)}")
    large = texts(w.large_layout)
    for title in ("電量", "儲存空間", "開機時間", "系統版本"):
        check(f"W6 大尺寸有「{title}」", title in large, f"{large}")
    check("W7 時間用 DynamicDate", any(
        type(c).__name__ == "DynamicDate" for row in w.small_layout.rows
        if isinstance(row, list) for c in row))

print("\n【X】Color.dynamic patch")
check("X1 Pyto 19.0 bug 已繞過", g["BACKGROUND"].__py_color__[0] == "dyn")

print("\n【Y】格式化")
fb = g["format_bytes"]
check("Y1 十進制單位（同 iOS 設定一致）", fb(128_000_000_000) == "128.0 GB", fb(128_000_000_000))
check("Y2 細數字", fb(999) == "999 B" and fb(1500) == "2 KB", f"{fb(999)} {fb(1500)}")
check("Y3 TB", fb(1_000_000_000_000) == "1.00 TB", fb(1_000_000_000_000))
check("Y4 None → —", fb(None) == "—")
fu = g["format_uptime"]
check("Y5 開機時間", fu(90061) == "1 天 1 小時" and fu(3700) == "1 小時 1 分" and fu(59) == "0 分")

print("\n【Z】電量")
bs, bc = g["battery_symbol"], g["battery_color"]
check("Z1 圖示跟電量", [bs(x, False) for x in (1.0, 0.7, 0.5, 0.2, 0.05)] == [
    "battery.100percent", "battery.75percent", "battery.50percent",
    "battery.25percent", "battery.0percent"])
check("Z2 充電中用閃電", bs(0.3, True) == "battery.100percent.bolt")
check("Z3 低電紅色", bc(0.1, False) is g["RED"] and bc(0.3, False) is g["ORANGE"])
check("Z4 讀唔到電量唔 crash", g["format_battery"](None) == "—")
free, total = g["read_storage"]()
check("Z5 讀到儲存空間（statvfs 後備）", bool(total) and 0 <= free <= total, f"{free}/{total}")

print("\n" + "=" * 60)
print(f"通過 {len(PASS)}  失敗 {len(FAIL)}")
if FAIL:
    print("失敗："); [print("  -", f) for f in FAIL]
    sys.exit(1)
print("全部通過 ✓")
