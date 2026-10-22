"""測試 i_widget_launcher.py 的更新邏輯。

用本地 HTTP server 模擬 GitHub raw，跑齊四種情境：
  A. 有新版 → 下載、寫快取、執行新版
  B. 冇新版（指紋相同）→ 跳過網絡、用快取
  C. 新版語法錯 → 拒絕、繼續行舊快取（唔會炸 widget）
  D. 網絡死 / 404 → 用快取
  E. 全新安裝（冇快取）+ 網絡死 → 顯示離線 widget

widgets 用 mock（照抄 Pyto 真實 API 簽名）。
"""
import http.server
import os
import shutil
import socketserver
import sys
import tempfile
import threading
import types
from datetime import datetime, timedelta

# ---------------------------------------------------------------- mock widgets
class __PyColor__:
    @staticmethod
    def colorWithRed(r, green=0, blue=0, alpha=1): return ("rgb", r, green, blue, alpha)
    @staticmethod
    def colorWithLight(light, dark=None): return ("dyn", light, dark)

def check(_object, name, types_):
    for _type in types_:
        if isinstance(_object, _type): return
    raise TypeError("Invalid value type")

class Color:
    def __init__(self, c): self.__py_color__ = c
    @classmethod
    def rgb(cls, red, green, blue, alpha=1):
        for v in (red, green, blue):
            assert isinstance(v, float) and 0 <= v <= 1, f"rgb 要 0-1 float，收到 {v!r}"
        return cls(__PyColor__.colorWithRed(red, green, green, blue, alpha))
    @classmethod
    def dynamic(cls, light, dark):   # Pyto 19.0 有 bug 的寫法
        check(light, "light", Color)
        return cls(__PyColor__.colorWithLight(light.__py_color__, dark=dark.__py_color__))
    def __repr__(self): return f"Color({self.__py_color__[0]})"

DATE_STYLE_DATE, DATE_STYLE_OFFSET, DATE_STYLE_RELATIVE, DATE_STYLE_TIME, DATE_STYLE_TIMER = 0,1,2,3,4

class Font:
    def __init__(self, name, size): self.name, self.size = name, size
    @classmethod
    def system_font_of_size(cls, size): return cls("sys", size)
    @classmethod
    def bold_system_font_of_size(cls, size): return cls("bold", size)

class Padding:
    def __init__(self, top=0, bottom=0, left=0, right=0): pass

class Component:
    def __init__(self, *pos, **kw): self.__args, self.__kw = pos, kw
    def __repr__(self): return type(self).__name__

class Text(Component): pass
class DynamicDate(Component): pass
class SystemSymbol(Component): pass
class Spacer: pass

class WidgetLayout:
    def __init__(self): self.rows = []
    def add_row(self, row): self.rows.append(row)
    def add_vertical_spacer(self): self.rows.append("<v>")
    def add_vertical_divider(self): self.rows.append("|")

class Widget:
    def __init__(self):
        self.small_layout = WidgetLayout(); self.medium_layout = WidgetLayout()
        self.large_layout = WidgetLayout(); self.extra_large_layout = WidgetLayout()

SHOWN = []
RELOADS = []
def show_widget(w): SHOWN.append(w)
def schedule_next_reload(t): RELOADS.append(t)

wd = types.ModuleType("widgets")
for k, v in list(globals().items()):
    if k in ("Color","Font","Padding","Text","DynamicDate","SystemSymbol","Spacer","Widget",
             "WidgetLayout","DATE_STYLE_DATE","DATE_STYLE_OFFSET","DATE_STYLE_RELATIVE",
             "DATE_STYLE_TIME","DATE_STYLE_TIMER","show_widget","schedule_next_reload"):
        setattr(wd, k, v)
for n in ["SECONDARY_LABEL","SYSTEM_GREEN","SYSTEM_ORANGE","SYSTEM_RED","LABEL"]:
    setattr(wd, f"COLOR_{n}", Color(f"const:{n}"))
sys.modules["widgets"] = wd


# ---------------------------------------------------------------- mock userkeys
# 官方 userkeys = NSUserDefaults suite "group.pyto"，extension 同主 app 共用。
# 呢個 mock 用一個全域 dict 模擬「跨執行持久」。
UK_STORE = {}
UK_BROKEN = False

def _uk_get(key):
    if UK_BROKEN:
        raise RuntimeError("NSUserDefaults unavailable")
    if key not in UK_STORE:
        raise KeyError(key)          # 官方 get() 對冇呢個 key 會 raise KeyError
    return UK_STORE[key]

def _uk_set(value, key):
    if UK_BROKEN:
        raise RuntimeError("NSUserDefaults unavailable")
    UK_STORE[key] = value

def _uk_delete(key):
    if key not in UK_STORE:
        raise KeyError(key)
    del UK_STORE[key]

uk = types.ModuleType("userkeys")
uk.get, uk.set, uk.delete = _uk_get, _uk_set, _uk_delete
sys.modules["userkeys"] = uk

# ---------------------------------------------------------------- fake GitHub
SERVE = {}          # {"fp": "v1", "py": "<code>"}
HITS = []

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        HITS.append(self.path)
        if self.path == "/i_widget.fingerprint":
            if SERVE.get("fp") is None:
                self.send_error(404); return
            body = SERVE["fp"].encode()
        elif self.path == "/i_widget.py":
            if SERVE.get("py") is None:
                self.send_error(404); return
            body = SERVE["py"].encode()
        else:
            self.send_error(404); return
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *a): pass

class _Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True

httpd = _Server(("127.0.0.1", 0), Handler)
PORT = httpd.server_address[1]
SERVERS = []


def _serve(server):
    """起一個背景 thread 跑 server，並保留引用避免被 GC。"""
    SERVERS.append(server)          # 保住 server 對象
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    SERVERS.append(thread)
    return server


_serve(httpd)
BASE = f"http://127.0.0.1:{PORT}"

# ---------------------------------------------------------------- 被測程式
LAUNCHER = "/home/wsluser/I-widget/i_widget_launcher.py"
GOOD_V1 = '''import widgets as wd
VERSION = "v1"
widget = wd.Widget()
for L in (widget.small_layout, widget.medium_layout, widget.large_layout, widget.extra_large_layout):
    L.add_row([wd.Text("version v1")])
wd.schedule_next_reload(__import__("datetime").timedelta(minutes=15))
wd.show_widget(widget)
'''

GOOD_V2 = GOOD_V1.replace("v1", "v2")
BROKEN = (
    "# " + ("padding line to make this exceed the 200 char guard. " * 5) + "\n"
    "def broken(:\n"
    "    this is definitely not valid python !!!\n"
)


def _text_of(component):
    """Text 的文字可能在位置參數或 kwargs，兩邊都試。"""
    args = getattr(component, "_Component__args", ())
    kw = getattr(component, "_Component__kw", {})
    return args[0] if args else kw.get("text")

def run_launcher(workdir, reset_userkeys=True, base=None):
    """喺指定目錄跑 launcher，回傳 (顯示咗咩, 執行咗咩版本)。"""
    shutil.copy(LAUNCHER, os.path.join(workdir, "i_widget_launcher.py"))
    src = open(os.path.join(workdir, "i_widget_launcher.py")).read()
    src = src.replace('SOURCE = "https://raw.githubusercontent.com/iceninye/I-widget/main"',
                      f'SOURCE = "{base or BASE}"')
    path = os.path.join(workdir, "i_widget_launcher.py")
    open(path, "w").write(src)

    SHOWN.clear(); RELOADS.clear(); HITS.clear()
    g = {"__name__": "__main__", "__file__": path}
    try:
        exec(compile(src, path, "exec"), g)
        err = None
    except Exception as e:
        err = e
    version = None
    if SHOWN:
        for row in SHOWN[0].small_layout.rows:
            if isinstance(row, list) and row and hasattr(row[0], "_Component__args"):
                version = _text_of(row[0])
    return SHOWN[0] if SHOWN else None, version, err

def cache_exists(workdir):
    return os.path.exists(os.path.join(workdir, "i_widget.cached.py"))

def fresh():
    d = tempfile.mkdtemp(prefix="iwtest_")
    return d

PASS, FAIL = [], []
def check(name, cond, detail=""):
    (PASS if cond else FAIL).append(name)
    print(f"  {'✓' if cond else '✗ FAIL'}  {name}{('  → ' + detail) if detail and not cond else ''}")

# ================================================================ 情境 A
print("\n【A】全新安裝 + 遠端有 v1")
SERVE.update(fp="v1", py=GOOD_V1); HITS.clear()
d = fresh()
UK_STORE.clear()
w, ver, err = run_launcher(d)
check("A1 顯示咗 widget", w is not None, f"err={err}")
check("A2 執行 v1", ver == "version v1", f"ver={ver}")
check("A3 寫咗快取", cache_exists(d))
check("A4 reload 已排程", len(RELOADS) == 1 and RELOADS[0] == timedelta(minutes=15), f"{RELOADS}")

# ================================================================ 情境 B
print("\n【B】遠端冇改（指紋相同）→ 唔應該重下載")
HITS.clear()
w, ver, err = run_launcher(d)
check("B1 仍然顯示 v1", ver == "version v1", f"ver={ver}")
check("B2 完全冇打網絡", len(HITS) == 0, f"HITS={HITS}")

# ================================================================ 情境 C
print("\n【C】推咗個壞版本去 main → 必須拒絕，繼續行 v1")
SERVE.update(fp="v2-broken", py=BROKEN); HITS.clear()
# 過咗節流窗口，迫佢再查
UK_STORE["i_widget.last_checked"] = 1.0  # 極舊 → 過咗節流窗口
w, ver, err = run_launcher(d)
check("C1 拒絕壞版本，仍行 v1", ver == "version v1", f"ver={ver} err={err}")
check("C2 快取冇被污染", "v1" in open(os.path.join(d, "i_widget.cached.py")).read())
check("C3 指紋冇被更新（下次會再試）",
      UK_STORE.get("i_widget.cached_fingerprint") == "v1"
      and open(os.path.join(d, "i_widget.cached.fingerprint")).read().strip() == "v1")

# ================================================================ 情境 D
print("\n【D】好更新：v2")
SERVE.update(fp="v2", py=GOOD_V2); HITS.clear()
UK_STORE["i_widget.last_checked"] = 1.0  # 極舊 → 過咗節流窗口
w, ver, err = run_launcher(d)
check("D1 執行咗 v2", ver == "version v2", f"ver={ver} err={err}")
check("D2 快取已更新", "v2" in open(os.path.join(d, "i_widget.cached.py")).read())

# ================================================================ 情境 E
print("\n【E】網絡死（server 收埋）+ 有快取 → 用快取")
httpd.shutdown()
w, ver, err = run_launcher(d)
check("E1 仍然出 widget", w is not None, f"err={err}")
check("E2 用返快取 v2", ver == "version v2", f"ver={ver}")

# ================================================================ 情境 F
print("\n【F】全新安裝 + 完全冇網絡 → 顯示離線 widget（唔會空白）")
d2 = fresh()
UK_STORE.clear()
w, ver, err = run_launcher(d2)
check("F1 顯示咗離線 widget", w is not None, f"err={err}")
if w:
    texts = [_text_of(c) for r in w.small_layout.rows
             if isinstance(r, list) for c in r if hasattr(c, "_Component__args")]
    check("F2 有講明『更新失敗』", any("更新失敗" in (t or "") for t in texts), f"{texts}")
check("F3 reload 已排程（會自動再試）", len(RELOADS) == 1, f"{RELOADS}")

# ================================================================ 情境 G
print("\n【G】404（遠端刪咗檔案）→ 唔會 crash")
SERVE.update(fp=None, py=None)
# 重開 server
httpd2 = _Server(("127.0.0.1", 0), Handler)
PORT2 = httpd2.server_address[1]
_serve(httpd2)
d3 = fresh()
UK_STORE.clear()
src = open(LAUNCHER).read().replace(
    'SOURCE = "https://raw.githubusercontent.com/iceninye/I-widget/main"',
    f'SOURCE = "http://127.0.0.1:{PORT2}"')
p3 = os.path.join(d3, "i_widget_launcher.py"); open(p3, "w").write(src)
SHOWN.clear(); RELOADS.clear()
try:
    exec(compile(src, p3, "exec"), {"__name__": "__main__", "__file__": p3})
    err = None
except Exception as e:
    err = e
check("G1 冇 crash", err is None, f"err={type(err).__name__}: {err}")
check("G2 顯示咗離線 widget", len(SHOWN) == 1)


# ================================================================ 情境 H
# 情境 E 關咗 server，H/I 需要服務器 → 用同一個 Handler 開返一個新 port
httpd2 = _Server(("127.0.0.1", 0), Handler)
PORT2 = httpd2.server_address[1]
_serve(httpd2)
BASE2 = f"http://127.0.0.1:{PORT2}"

print("\n【H】userkeys 持久化：extension 每次 reload 係全新 sandbox")
# 關鍵：每次 reload Pyto 會複製 script 去新路徑，所以工作目錄唔同、
# 檔案快取會唔見。userkeys（NSUserDefaults suite）先可以跨 reload 保住。
SERVE.update(fp="v1", py=GOOD_V1); HITS.clear()
UK_STORE.clear()
d_first = fresh()
w, ver, err = run_launcher(d_first, base=BASE2)
check("H1 第一次執行 v1", ver == "version v1", f"ver={ver}")
check("H2 userkeys 有存程式碼", bool(UK_STORE.get("i_widget.cached_code")))
check("H3 userkeys 有存指紋", UK_STORE.get("i_widget.cached_fingerprint") == "v1")

# 模擬下一次 reload：全新目錄（檔案快取冇），但 userkeys 應該仲喺度
HITS.clear()
d_second = fresh()
check("H4 新目錄冇檔案快取", not os.path.exists(os.path.join(d_second, "i_widget.cached.py")))
w, ver, err = run_launcher(d_second, reset_userkeys=False, base=BASE2)
check("H5 靠 userkeys 讀到 v1（冇重新落載）", ver == "version v1", f"ver={ver}")
check("H6 完全冇打網絡", len(HITS) == 0, f"HITS={HITS}")

# ================================================================ 情境 I
print("\n【I】userkeys 壞咗 → 自動 fallback 檔案")
SERVE.update(fp="v1", py=GOOD_V1)   # G 情境 set 咗 None，要重新擺返內容
HITS.clear()
UK_STORE.clear()
UK_BROKEN = True
try:
    d3b = fresh()
    w, ver, err = run_launcher(d3b, base=BASE2)
    check("I1 userkeys 壞咗仍執行到 v1", ver == "version v1", f"ver={ver} err={err}")
    check("I2 已改用檔案快取", os.path.exists(os.path.join(d3b, "i_widget.cached.py")))

    # 節流：userkeys 壞咗，應該靠檔案 CACHED_CHECKED 判斷
    # （touch_checked 兩邊都會寫，檔案嗰個剛寫過 → 應該唔打網絡）
    HITS.clear()
    w, ver, err = run_launcher(d3b, base=BASE2)
    check("I3 靠檔案 mtime 節流，零網絡", len(HITS) == 0, f"HITS={HITS}")
    check("I4 仍然係 v1", ver == "version v1", f"ver={ver}")
finally:
    UK_BROKEN = False

print("\n" + "=" * 60)
print(f"通過 {len(PASS)}  失敗 {len(FAIL)}")
if FAIL:
    print("失敗："); [print("  -", f) for f in FAIL]
    sys.exit(1)
print("全部通過 ✓")