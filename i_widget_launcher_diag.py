"""
i-widget LAUNCHER SELF-DIAG — launcher 自我診斷版。

背景
----
`i_widget_safe.py`（4.6 KB）真機正常，但 `i_widget_launcher.py`（19 KB）
長期只見綠色 default template。已排除：
  - COLOR_SECONDARY_LABEL 唔存在 → 錯（probe 話存在）
  - __file__ 冇定義         → 錯（probe 話有）
  - hashlib C extension      → 錯（CPython 自動 fallback）
  - Color.dynamic 壞        → 真係壞，已修
  - 網絡 / exec / userkeys  → probe 話全部 OK

即係話「有樣嘢我哋仲未知」。

呢個版本做一件事：**無論死喺邊，都將原因畫出嚟。**

關鍵設計（來自 diag 教訓）：
  `show_widget()` 一個 script run **只理第一次**，之後被忽略。
  → 所以所有診斷資訊收集齊，最後**只叫一次** `show_widget()`。

流程：
  1. 記錄「開始」
  2. 逐步執行 launcher 嘅真實流程（下載 / 快取 / compile / exec）
  3. 每一個 catch 都記低錯誤
  4. 最後一次 show_widget()，一次過顯示全部診斷

用法：呢個檔案代替 i_widget_launcher.py 放喺 Pyto。
"""

DIAG_LAUNCHER = "launcher-diag-1.0"

import widgets as wd

LOG = []


def step(label):
    LOG.append(("→ " + label, ""))


def fail(label, error):
    LOG.append(("✗ " + label, f"{type(error).__name__}: {str(error)[:70]}"))


def ok(label, value=""):
    LOG.append(("✓ " + label, str(value)[:60]))


# --- 修補 Pyto 官方 Color.dynamic bug（真機實測會擲 TypeError）----------
def _patch_color_dynamic():
    try:
        white = wd.Color.rgb(1.0, 1.0, 1.0)
        black = wd.Color.rgb(0.0, 0.0, 0.0)
    except BaseException as error:
        fail("patch 前置 rgb", error)
        return
    try:
        wd.Color.dynamic(light=white, dark=black)
        ok("Color.dynamic 本來正常")
        return
    except BaseException:
        step("偵測到 Color.dynamic 有 bug，開始 patch")
    try:
        from widgets import Color, __PyColor__

        def _dynamic(light, dark):
            return Color(__PyColor__.colorWithLight(
                light.__py_color__, dark=dark.__py_color__))

        Color.dynamic = staticmethod(_dynamic)
        ok("patch 成功")
    except BaseException as error:
        fail("patch 失敗", error)


_patch_color_dynamic()

# --- launcher 真實流程逐步執行 --------------------------------------------
SOURCE = "https://raw.githubusercontent.com/iceninye/I-widget/main"
FP_URL = f"{SOURCE}/i_widget.fingerprint"
PY_URL = f"{SOURCE}/i_widget.py"
TIMEOUT = 12


def fetch(url):
    from urllib.request import Request, urlopen

    r = urlopen(Request(url, headers={"User-Agent": "i-widget-diag"}), timeout=TIMEOUT)
    return r.read().decode("utf-8", "replace")


# 1. 指紋
remote_fp = None
try:
    remote_fp = fetch(FP_URL).strip()
    ok("下載指紋", remote_fp[:14])
except BaseException as error:
    fail("下載指紋", error)

# 2. 程式碼
code = None
try:
    code = fetch(PY_URL)
    ok("下載 i_widget.py", f"{len(code)} bytes")
except BaseException as error:
    fail("下載 i_widget.py", error)

# 3. 快取
try:
    import userkeys

    cached_code = None
    try:
        cached_code = userkeys.get("i_widget.cached_code")
    except BaseException as error:
        fail("userkeys.get", error)
    cached_fp = None
    try:
        cached_fp = userkeys.get("i_widget.cached_fingerprint")
    except BaseException as error:
        fail("userkeys.get fp", error)
    ok("userkeys", f"code={len(cached_code) if cached_code else 0}B fp={cached_fp}")
except BaseException as error:
    fail("import userkeys", error)

# 4. compile
compiled = None
if code:
    try:
        compiled = compile(code, "i_widget.py", "exec")
        ok("compile i_widget.py", "OK")
    except BaseException as error:
        fail("compile i_widget.py", error)

# 5. exec（唔叫 show_widget — 會搶走唯一一次機會）
if compiled is not None:
    try:
        ns = {"__name__": "diag_probe", "__file__": "/tmp/i_widget.py"}
        # 攔截 show_widget，唔想佢真正顯示（我最後自己畫）
        captured = []

        class FakeWidget:
            def __init__(self, *a, **k):
                self.small_layout = _FakeLayout()
                self.medium_layout = _FakeLayout()
                self.large_layout = _FakeLayout()
                self.extra_large_layout = _FakeLayout()
                self.background_color = None

        class _FakeLayout:
            def add_vertical_spacer(self, *a, **k):
                pass

            def add_row(self, *a, **k):
                pass

            def set_background_color(self, *a, **k):
                pass

            def add_vertical_divider(self, *a, **k):
                pass

        wd.Widget = FakeWidget
        wd.show_widget = lambda w=None: captured.append(w)

        exec(compiled, ns)
        ok("exec i_widget.py", "模組層跑完（show_widget 被攔截）")
        if captured:
            ok("widget 有叫 show_widget", f"{len(captured)} 次")
        else:
            step("⚠️ i_widget.py 冇叫 show_widget → 佢自己死咗")
    except BaseException as error:
        fail("exec i_widget.py", error)
        import traceback
        tb = traceback.format_exc().strip().split("\n")
        for line in tb[-4:]:
            LOG.append(("  " + line.strip()[:62], ""))

# --- 唯一一次 show_widget()：顯示全部診斷 ---------------------------------
def render():
    BG = wd.Color.rgb(0.08, 0.08, 0.09)
    FG = wd.Color.rgb(1, 1, 1)
    DIM = wd.Color.rgb(0.62, 0.62, 0.68)
    RED = wd.Color.rgb(1.0, 0.36, 0.30)
    GRN = wd.Color.rgb(0.35, 0.85, 0.45)

    w = wd.Widget()
    try:
        w.background_color = BG
    except BaseException:
        pass

    lines = [(f"launcher diag {DIAG_LAUNCHER}", 9, DIM)]
    lines.append((f"共 {len(LOG)} 項", 9, DIM))
    for label, value in LOG:
        color = DIM
        if label.startswith("✗"):
            color = RED
        elif label.startswith("✓"):
            color = GRN
        lines.append((label, 10, color))
        if value:
            lines.append(("    " + value, 9, DIM))

    for name in ("small_layout", "medium_layout", "large_layout"):
        layout = getattr(w, name, None)
        if layout is None:
            continue
        layout.add_vertical_spacer()
        for text, size, color in lines:
            f = wd.Font.system_font_of_size(size)
            layout.add_row([wd.Text(text, font=f, color=color)])
        layout.add_vertical_spacer()
        try:
            layout.set_background_color(BG)
        except BaseException:
            pass

    from datetime import timedelta

    try:
        wd.schedule_next_reload(timedelta(minutes=30))
    except BaseException:
        pass
    wd.show_widget(w)


try:
    render()
except BaseException as error:
    try:
        w2 = wd.Widget()
        w2.small_layout.add_row([wd.Text(f"render 死: {type(error).__name__}")])
        wd.show_widget(w2)
    except BaseException:
        pass