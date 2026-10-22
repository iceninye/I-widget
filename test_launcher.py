"""測試 i_widget_launcher.py 的更新邏輯。

用本地 HTTP server 模擬 GitHub raw，跑齊 A–P 情境（每個情境見下面標題）。

widgets／userkeys 用 mock_pyto.py（照抄 Pyto 真實 API 簽名）。
"""
import http.server
import os
import shutil
import socketserver
import sys
import tempfile
import threading
import hashlib
from datetime import datetime, timedelta

# ---------------------------------------------------------------- mock Pyto
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from mock_pyto import RELOADS, SHOWN, UK_STATE, UK_STORE, text_of as _text_of  # noqa: E402

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
LAUNCHER = os.path.join(HERE, "i_widget_launcher.py")
launcher_src = open(LAUNCHER).read()
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


def fp_of(code):
    """同 make_fingerprint.py 一樣：SHA256 前 16 字元，再加 GitHub 上面嗰個換行。"""
    return hashlib.sha256(code.encode("utf-8")).hexdigest()[:16] + "\n"


FP_V1, FP_V2, FP_BROKEN = fp_of(GOOD_V1), fp_of(GOOD_V2), fp_of(BROKEN)

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
SERVE.update(fp=FP_V1, py=GOOD_V1); HITS.clear()
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
SERVE.update(fp=FP_BROKEN, py=BROKEN); HITS.clear()
# 過咗節流窗口，迫佢再查
UK_STORE["i_widget.last_checked"] = 1.0  # 極舊 → 過咗節流窗口
w, ver, err = run_launcher(d)
check("C1 拒絕壞版本，仍行 v1", ver == "version v1", f"ver={ver} err={err}")
check("C2 快取冇被污染", "v1" in open(os.path.join(d, "i_widget.cached.py")).read())
check("C3 指紋冇被更新（下次會再試）",
      UK_STORE.get("i_widget.cached_fingerprint") == FP_V1.strip()
      and open(os.path.join(d, "i_widget.cached.fingerprint")).read().strip() == FP_V1.strip())

# ================================================================ 情境 D
print("\n【D】好更新：v2")
SERVE.update(fp=FP_V2, py=GOOD_V2); HITS.clear()
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
SERVE.update(fp=FP_V1, py=GOOD_V1); HITS.clear()
UK_STORE.clear()
d_first = fresh()
w, ver, err = run_launcher(d_first, base=BASE2)
check("H1 第一次執行 v1", ver == "version v1", f"ver={ver}")
check("H2 userkeys 有存程式碼", bool(UK_STORE.get("i_widget.cached_code")))
check("H3 userkeys 有存指紋", UK_STORE.get("i_widget.cached_fingerprint") == FP_V1.strip())

# 模擬下一次 reload：全新目錄（檔案快取冇），但 userkeys 應該仲喺度
HITS.clear()
d_second = fresh()
check("H4 新目錄冇檔案快取", not os.path.exists(os.path.join(d_second, "i_widget.cached.py")))
w, ver, err = run_launcher(d_second, reset_userkeys=False, base=BASE2)
check("H5 靠 userkeys 讀到 v1（冇重新落載）", ver == "version v1", f"ver={ver}")
check("H6 完全冇打網絡", len(HITS) == 0, f"HITS={HITS}")

# ================================================================ 情境 I
print("\n【I】userkeys 壞咗 → 自動 fallback 檔案")
SERVE.update(fp=FP_V1, py=GOOD_V1)   # G 情境 set 咗 None，要重新擺返內容
HITS.clear()
UK_STORE.clear()
UK_STATE["broken"] = True
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
    UK_STATE["broken"] = False


# ================================================================ 情境 J
print("\n【J】iOS 27 適應：reload 預算 + coalescing 防護")
import re as _re

# J1/J2: i_widget.py 嘅 reload 間隔要喺 WidgetKit 每日預算內
# Apple: 40–70 reloads per 24h。15 分鐘 = 96 次 = 超標。
widget_src = open(os.path.join(HERE, "i_widget.py")).read()
m = _re.search(r"RELOAD_INTERVAL\s*=\s*timedelta\(minutes=(\d+)\)", widget_src)
minutes = int(m.group(1)) if m else 0
per_day = int(24 * 60 / minutes) if minutes else 999
check("J1 reload 間隔有設定", minutes > 0, f"minutes={minutes}")
check(f"J2 {minutes} 分鐘 = {per_day} 次/日，喺 Apple 40–70 預算內", per_day <= 70, f"per_day={per_day}")

# J3: launcher 嘅 CHECK_INTERVAL 唔應該細過 reload 間隔
# （細過的話每個新 sandbox 都會問 GitHub，節流失效）
m2 = _re.search(r"CHECK_INTERVAL\s*=\s*(\d+)\s*\*\s*60", launcher_src)
check_secs = int(m2.group(1)) * 60 if m2 else 0
check("J3 CHECK_INTERVAL 唔細過 reload 間隔",
      check_secs >= minutes * 60, f"CHECK_INTERVAL={check_secs}s, reload={minutes * 60}s")

# J4: coalescing 防護存在，而且會喺寫入之後叫
check("J4 有 coalescing 防護（_yield_after_write）",
      "_yield_after_write" in launcher_src)
save_body = launcher_src[launcher_src.find("def save("):launcher_src.find("def touch_checked")]
check("J5 save() 寫入之後有 yield", "_yield_after_write()" in save_body)

# J6: 離線 widget 都用同一個間隔，唔會離線時問得更密
check("J6 離線 widget 用 30 分鐘", "timedelta(minutes=30)" in launcher_src)


# ================================================================ 情境 K
print("\n【K】userkeys 壞咗 + 指紋冇變 → 唔應該重新落載程式碼（換行 bug 回歸測試）")
# GitHub 上面嘅指紋檔有結尾換行，檔案快取讀返嚟係 strip 咗嘅。
# 以前兩邊直接比較 → 永遠唔相等 → 每次都重新落載完整程式碼。
SERVE.update(fp=FP_V1, py=GOOD_V1)
UK_STORE.clear()
UK_STATE["broken"] = True
try:
    dk = fresh()
    run_launcher(dk, base=BASE2)
    open(os.path.join(dk, "i_widget.last_checked"), "w").write("1.0")  # 過咗節流窗口
    HITS.clear()
    w, ver, err = run_launcher(dk, base=BASE2)
    check("K1 仍然係 v1", ver == "version v1", f"ver={ver} err={err}")
    check("K2 淨係問咗指紋，冇重新落載", HITS == ["/i_widget.fingerprint"], f"HITS={HITS}")
finally:
    UK_STATE["broken"] = False

# ================================================================ 情境 L
print("\n【L】指紋同程式碼對唔上（CDN 快取未同步／下載唔完整）→ 拒絕")
dl = fresh()
UK_STORE.clear()
SERVE.update(fp=FP_V1, py=GOOD_V1)
run_launcher(dl, base=BASE2)
SERVE.update(fp=FP_V2, py=GOOD_V1.replace("v1", "vX"))   # 新指紋，但內容唔係嗰個版本
UK_STORE["i_widget.last_checked"] = 1.0
w, ver, err = run_launcher(dl, base=BASE2)
check("L1 拒絕對唔上嘅程式碼，仍行 v1", ver == "version v1", f"ver={ver} err={err}")
check("L2 指紋冇更新（下次再試）", UK_STORE.get("i_widget.cached_fingerprint") == FP_V1.strip())
check("L3 冇蓋節流時間（下次 reload 即刻再試）", UK_STORE.get("i_widget.last_checked") == 1.0,
      f"{UK_STORE.get('i_widget.last_checked')}")
SERVE.update(fp=FP_V2, py=GOOD_V2)                        # CDN 追返上
w, ver, err = run_launcher(dl, base=BASE2)
check("L4 CDN 同步後自動攞到 v2", ver == "version v2", f"ver={ver}")

# ================================================================ 情境 M
print("\n【M】超大回應 → 唔讀入記憶體")
dm = fresh()
UK_STORE.clear()
huge = "# " + "x" * (600 * 1024) + "\n" + GOOD_V1
SERVE.update(fp=fp_of(huge), py=huge)
w, ver, err = run_launcher(dm, base=BASE2)
check("M1 冇執行超大檔案", ver != "version v1", f"ver={ver}")
check("M2 冇 crash，出咗離線 widget", w is not None and err is None, f"err={err}")

# ================================================================ 情境 N
print("\n【N】節流窗口有容差：reload 準時 30 分鐘都要檢查")
dn = fresh()
UK_STORE.clear()
SERVE.update(fp=FP_V1, py=GOOD_V1)
run_launcher(dn, base=BASE2)
import time as _time
UK_STORE["i_widget.last_checked"] = _time.time() - 30 * 60 + 5   # 差 5 秒先夠 30 分鐘
HITS.clear()
run_launcher(dn, base=BASE2)
check("N1 iOS 早少少 reload 都照樣檢查", "/i_widget.fingerprint" in HITS, f"HITS={HITS}")
UK_STORE["i_widget.last_checked"] = _time.time() - 5 * 60
HITS.clear()
run_launcher(dn, base=BASE2)
check("N2 5 分鐘前查過 → 唔打網絡", HITS == [], f"HITS={HITS}")

# ================================================================ 情境 O
print("\n【O】首次安裝、指紋檔攞唔到但程式碼攞到 → 存真指紋，唔係 'unverified'")
do = fresh()
UK_STORE.clear()
SERVE.update(fp=None, py=GOOD_V1)
w, ver, err = run_launcher(do, base=BASE2)
check("O1 執行咗 v1", ver == "version v1", f"ver={ver} err={err}")
check("O2 存咗程式碼本身嘅指紋", UK_STORE.get("i_widget.cached_fingerprint") == FP_V1.strip(),
      f"{UK_STORE.get('i_widget.cached_fingerprint')}")
SERVE.update(fp=FP_V1, py=GOOD_V1)
UK_STORE["i_widget.last_checked"] = 1.0
HITS.clear()
run_launcher(do, base=BASE2)
check("O3 之後指紋一樣 → 唔重新落載", HITS == ["/i_widget.fingerprint"], f"HITS={HITS}")

# ================================================================ 情境 P
print("\n【P】端到端：真嘅 i_widget.py + make_fingerprint.py 產生嘅指紋")
import pathlib  # noqa: E402

import make_fingerprint  # noqa: E402

real_py = open(os.path.join(HERE, "i_widget.py"), encoding="utf-8").read()
# 用 make_fingerprint.py 本身嘅函數，唔讀 i_widget.fingerprint 檔：
# push 去 main 之後、Action 補指紋之前，個檔係會過時一陣嘅。
real_fp = make_fingerprint.fingerprint(pathlib.Path(HERE) / "i_widget.py") + "\n"
SERVE.update(fp=real_fp, py=real_py)
dp = fresh()
UK_STORE.clear()
w, ver, err = run_launcher(dp, base=BASE2)
check("P1 指紋同內容對得上（兩邊算法一致）", real_fp.strip() == fp_of(real_py).strip(),
      f"{real_fp.strip()} != {fp_of(real_py).strip()}")
check("P2 落載並執行真 widget", w is not None and err is None, f"err={err}")
check("P3 已寫入快取", UK_STORE.get("i_widget.cached_code") == real_py)

print("\n" + "=" * 60)
print(f"通過 {len(PASS)}  失敗 {len(FAIL)}")
if FAIL:
    print("失敗："); [print("  -", f) for f in FAIL]
    sys.exit(1)
print("全部通過 ✓")