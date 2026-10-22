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
check("W3 reload 唔超過 30 分鐘", len(RELOADS) == 1 and timedelta(0) < RELOADS[0] <= timedelta(minutes=30), f"{RELOADS}")

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


print("\n【R】崩潰自癒：上次有元件令 process 死咗，今次要跳過佢")
import time as _time  # noqa: E402
from mock_pyto import UK_STORE  # noqa: E402


def run_widget():
    SHOWN.clear()
    g2 = {"__name__": "__main__", "__file__": path}
    exec(compile(open(path, encoding="utf-8").read(), path, "exec"), g2)
    return SHOWN[0] if SHOWN else None


def c_kw(component):
    return getattr(component, "_Component__kw", {})


def kinds(layout):
    return {type(c).__name__ for row in layout.rows if isinstance(row, list) for c in row}


EPOCH = str(g["BAN_EPOCH"])


def fresh_store(**keys):
    UK_STORE.clear()
    UK_STORE["i_widget.ban_epoch"] = EPOCH
    UK_STORE.update({f"i_widget.{k}": v for k, v in keys.items()})


def all_time_style(w):
    nodes = [c for r in w.small_layout.rows if isinstance(r, list) for c in r if type(c).__name__ == "DynamicDate"]
    return bool(nodes) and all(c_kw(c).get("style") == 3 for c in nodes)   # DATE_STYLE_TIME


# 第一次死：只記一筆，唔停用（可能係多個 process 同時死造成嘅誤判）
fresh_store(inflight=f"clock_timer|{_time.time() - 60}")
g["_recover_from_crash"]()
check("R2a 偵測後只記 1 次，未停用",
      UK_STORE.get("i_widget.strikes") == "clock_timer:1" and not UK_STORE.get("i_widget.banned"),
      f"{UK_STORE.get('i_widget.strikes')!r} / {UK_STORE.get('i_widget.banned')!r}")
fresh_store(inflight=f"clock_timer|{_time.time() - 60}")
w = run_widget()
check("R1 照樣 show_widget", w is not None)
check("R2 死一次唔停用", "clock_timer" not in UK_STORE.get("i_widget.banned", ""), UK_STORE.get("i_widget.banned", ""))
check("R5 順利砌完後標記已清", UK_STORE.get("i_widget.inflight") == "")
check("R5b 成功一次就清零 strikes", UK_STORE.get("i_widget.strikes") == "")

# 連續死兩次：停用，自動換下一個寫法
fresh_store(inflight=f"clock_timer|{_time.time() - 60}", strikes="clock_timer:1")
w = run_widget()
check("R3 連續死兩次 → 停用", "clock_timer" in UK_STORE.get("i_widget.banned", ""), UK_STORE.get("i_widget.banned", ""))
check("R3b 自動換下一個寫法（仍然用 DynamicDate）", "DynamicDate" in kinds(w.small_layout), f"{kinds(w.small_layout)}")
check("R3c 停用計時器後改用 TIME 樣式", all_time_style(w))
w = run_widget()
check("R6 之後每輪都繼續跳過 clock_timer", all_time_style(w))

# 全部 DynamicDate 寫法都死過 → 靜態文字，仍然有時間
fresh_store(banned="clock_timer,clock_font,clock_color,clock_plain")
w = run_widget()
check("R6b 全部停用 → 唔用 DynamicDate", "DynamicDate" not in kinds(w.small_layout), f"{kinds(w.small_layout)}")
check("R6c 靜態時間照出", any(":" in (text_of(c) or "") for r in w.small_layout.rows
      if isinstance(r, list) for c in r if isinstance(c, Text)))

# 標記好新鮮 = 另一個 process 同時跑緊，唔係崩潰
fresh_store(inflight=f"clock_timer|{_time.time()}", strikes="clock_timer:1")
w = run_widget()
check("R7 新鮮標記唔會誤殺", "clock_timer" not in UK_STORE.get("i_widget.banned", ""))
check("R8 DynamicDate 照用", "DynamicDate" in kinds(w.small_layout))

# 所有有風險元件都停用，widget 仍然要有內容
fresh_store(banned="clock_timer,clock_font,clock_color,clock_plain,icon,spacer,divider,background")
w = run_widget()
big = [text_of(c) for r in w.large_layout.rows if isinstance(r, list) for c in r if isinstance(c, Text)]
check("R9 全部停用都出到大尺寸內容", w is not None and "電量" in big and "儲存空間" in big, f"{big}")
check("R10 冇用到被停用嘅元件",
      not ({"DynamicDate", "SystemSymbol", "Spacer"} & kinds(w.large_layout)), f"{kinds(w.large_layout)}")
check("R11 有足跡", "show_widget 已叫" in UK_STORE.get("i_widget.trace2", ""))

# 版本變咗（例如舊誤判）→ 自動清走停用名單，用戶唔使手動 userkeys.set
UK_STORE.clear()
UK_STORE["i_widget.ban_epoch"] = "1"
UK_STORE["i_widget.banned"] = "clock,spacer"
w = run_widget()
check("R12 舊版本停用名單自動清走", UK_STORE.get("i_widget.banned") == "", UK_STORE.get("i_widget.banned"))
check("R13 之後版本號更新", UK_STORE.get("i_widget.ban_epoch") == EPOCH)
check("R14 Spacer 回復使用", "Spacer" in kinds(w.large_layout), f"{kinds(w.large_layout)}")

print("\n【L】版面：卡片、進度條、低耗電、邊距")
from mock_pyto import Widget  # noqa: E402

SYS = {"low_power": True, "version": "iOS 27.0.1", "uptime": 23 * 86400 + 18 * 3600}
fresh_store()
lw = Widget()
g["build_large"](lw.large_layout, datetime.now(), 0.75, False, 32_600_000_000, 255_400_000_000, SYS)
L = lw.large_layout
cards = [i for i, st in enumerate(L.row_styles) if st and st[0] is not None]
check("L1 大尺寸有 4 張資料卡（圓角底色）", len(cards) == 4, f"{len(cards)}")
check("L2 卡片有圓角", all(L.row_styles[i][1] > 0 for i in cards))
big = [text_of(c) for r in L.rows if isinstance(r, list) for c in r if isinstance(c, Text)]
check("L3 電量進度條", any("▰" in (t or "") and "▱" in (t or "") for t in big), f"{big}")
check("L4 低耗電唔再佔獨立一行", "低耗電模式" not in big and "已開啟" not in big)
check("L5 低耗電葉仔圖示喺頂部", any(type(c).__name__ == "SystemSymbol" for r in L.rows[:1]
      if isinstance(r, list) for c in r))
check("L6 儲存空間數值（單位只寫一次）", "32.6 / 255.4 GB" in big, f"{big}")
check("L7 每張卡都有 Spacer（數值靠右）", all(any(type(c).__name__ == "Spacer" for c in L.rows[i]) for i in cards))
check("L8 大尺寸總行數 ≤ 20（唔會溢出）", len(L.rows) <= 20, f"{len(L.rows)}")

sm = Widget()
g["build_small"](sm.small_layout, datetime.now(), 0.2, False, SYS)
check("L9 小尺寸電量偏低有紅色", any(c.__dict__.get("_Component__kw", {}).get("color") is g["RED"]
      for r in sm.small_layout.rows if isinstance(r, list) for c in r if isinstance(c, Text)))
md = Widget()
g["build_medium"](md.medium_layout, datetime.now(), 0.5, True, 32_600_000_000, 255_400_000_000, SYS)
mt = [text_of(c) for r in md.medium_layout.rows if isinstance(r, list) for c in r if isinstance(c, Text)]
check("L10 中尺寸有儲存空間", "32.6 GB 可用" in mt, f"{mt}")

# 卡片功能唔支援／死過 → 退返普通行，內容照出
fresh_store(banned="card")
lw = Widget()
g["_BANNED_NOW"].clear(); g["_BANNED_NOW"].add("card")
g["build_large"](lw.large_layout, datetime.now(), 0.75, False, 32_600_000_000, 255_400_000_000, SYS)
check("L11 卡片被停用 → 冇底色但內容照出",
      not any(st and st[0] is not None for st in lw.large_layout.row_styles)
      and "電量" in [text_of(c) for r in lw.large_layout.rows if isinstance(r, list) for c in r if isinstance(c, Text)])
g["_BANNED_NOW"].clear()

sb = g["segment_bar"]
check("L12 進度條 0／50／100%", sb(0) == "▱" * 10 and sb(0.5) == "▰" * 5 + "▱" * 5 and sb(1) == "▰" * 10 and sb(None) == "▱" * 10)

print("\n【N】標記只包 native 操作；iPhone 唔砌 extra large")
fresh_store()
lw = Widget()
g["_BANNED_NOW"].clear()
g["spacer"]()
check("N1 建 Spacer 唔會寫標記（純 Python）", UK_STORE.get("i_widget.inflight", "") == "", UK_STORE.get("i_widget.inflight"))
g["icon"]("battery.50percent")
check("N2 建 SystemSymbol 唔會寫標記", UK_STORE.get("i_widget.inflight", "") == "")

# 標記只喺 add_row 嗰一刻存在，之後即刻清走
seen = []
class Probe(mock_pyto.WidgetLayout):
    def add_row(self, row, **kw):
        seen.append(UK_STORE.get("i_widget.inflight", ""))
        return super().add_row(row, **kw)
pl = Probe()
g["place_clock"](pl, datetime(2026, 10, 23, 14, 5, 30), 44, [g["spacer"]()])
check("N3 add_row 時標記指向 clock_timer", seen and seen[0].startswith("clock_timer|"), f"{seen}")
check("N4 add_row 後標記已清", UK_STORE.get("i_widget.inflight") == "")

# DynamicDate 一加入就擲例外（Python 層面）→ 三種寫法逐個試，最後用靜態文字，例外唔會穿出去
class RejectsDynamicDate(mock_pyto.WidgetLayout):
    def add_row(self, row, **kw):
        if any(type(c).__name__ == "DynamicDate" for c in row):
            raise RuntimeError("DynamicDate 唔得")
        return super().add_row(row, **kw)
UK_STORE.clear(); UK_STORE["i_widget.ban_epoch"] = EPOCH
rl = RejectsDynamicDate()
g["place_clock"](rl, datetime(2026, 10, 23, 14, 5, 30), 44, [g["spacer"]()])
trace2 = UK_STORE.get("i_widget.trace2", "")
check("N5 四種 DynamicDate 寫法都試過", all(f"{n} 爆" in trace2 for n in ("clock_timer", "clock_font", "clock_color", "clock_plain")), trace2)
check("N6 最後用靜態時間，行有內容", len(rl.rows) == 1 and any(":" in (text_of(c) or "") for c in rl.rows[0] if isinstance(c, Text)),
      f"{rl.rows}")
check("N6b 標記已清", UK_STORE.get("i_widget.inflight") == "")

check("N7 iPhone 唔砌 extra large", g["family_names"](False) == ("small_layout", "medium_layout", "large_layout"))
check("N8 iPad 砌 extra large", "extra_large_layout" in g["family_names"](True))

print("\n【T】即時時鐘（計時器寫法）")
from mock_pyto import DATE_STYLE_TIMER, DATE_STYLE_TIME  # noqa: E402


def clock_nodes(layout):
    return [c for r in layout.rows if isinstance(r, list) for c in r if type(c).__name__ == "DynamicDate"]


noon = datetime(2026, 10, 23, 14, 5, 30)
fresh_store()
g["_BANNED_NOW"].clear()
tl = mock_pyto.WidgetLayout()
g["place_clock"](tl, noon, 44, [g["spacer"]()], timer_size=30)
node = clock_nodes(tl)[0]
kw = c_kw(node)
check("T1 日間用 TIMER 樣式", kw.get("style") == DATE_STYLE_TIMER, f"{kw}")
check("T2 由今日 00:00 起數", node._Component__args[0] == datetime(2026, 10, 23, 0, 0, 0), f"{node._Component__args}")
check("T3 用較細字體（hh:mm:ss 較闊）", kw["font"].size == 30, f"{kw['font'].size}")

night = datetime(2026, 10, 23, 0, 30, 0)
tl = mock_pyto.WidgetLayout()
g["place_clock"](tl, night, 44, [], timer_size=30)
kw = c_kw(clock_nodes(tl)[0])
check("T4 00:xx 唔用計時器（會顯示成分:秒）", kw.get("style") == DATE_STYLE_TIME, f"{kw}")

g["_BANNED_NOW"].clear(); g["_BANNED_NOW"].add("clock_timer")
tl = mock_pyto.WidgetLayout()
g["place_clock"](tl, noon, 44, [], timer_size=30)
check("T5 計時器死過 → 自動退返 TIME 樣式", c_kw(clock_nodes(tl)[0]).get("style") == DATE_STYLE_TIME)
g["_BANNED_NOW"].clear()

nd = g["next_reload_delay"]
check("T6 日間 reload 30 分鐘", nd(datetime(2026, 10, 23, 14, 0, 0)) == timedelta(minutes=30))
check("T7 23:50 要趕 00:00:20 reload", nd(datetime(2026, 10, 23, 23, 50, 0)) == timedelta(minutes=10, seconds=20), f"{nd(datetime(2026, 10, 23, 23, 50, 0))}")
check("T8 00:40 要趕 01:00:20 reload", nd(datetime(2026, 10, 23, 0, 40, 0)) == timedelta(minutes=20, seconds=20), f"{nd(datetime(2026, 10, 23, 0, 40, 0))}")
check("T9 00:00:20 之後唔會出負數", nd(datetime(2026, 10, 23, 0, 0, 20)) > timedelta(0))

print("\n" + "=" * 60)
print(f"通過 {len(PASS)}  失敗 {len(FAIL)}")
if FAIL:
    print("失敗："); [print("  -", f) for f in FAIL]
    sys.exit(1)
print("全部通過 ✓")
