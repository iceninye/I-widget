"""i-widget 本地快取啟動器 —— Pyto 遠端拉碼已封存。

封存原則：

* **永不發出遠端下載請求**，唔再更新 `i_widget.py` 或佢嘅指紋。
* 只執行先前已經存喺本地嘅快取；快取必須同時通過指紋、語法同
  `CACHE_MARKER` sanity 檢查。任何一項失敗都唔會 exec。
* 冷啟動冇可信快取時，唔會退回「下載 → compile → exec」嘅無驗證分支，
  而係顯示明確嘅封存／驗證錯誤。
* 本地快取仍可用；需要完全離線或者首次安裝時，請直接令 widget 指向
  `i_widget.py`。

用法：現有用戶可保留呢個 launcher 行驗證過嘅快取；新安裝請用本地模式。
"""

import os
import re
import time
from datetime import timedelta

import widgets as wd

# --- 設定 ---------------------------------------------------------------

# 封存前嘅 URL 只留作舊工具／測試參考；封存模式唔會讀取或下載。
SOURCE = "https://raw.githubusercontent.com/iceninye/I-widget/main"
FINGERPRINT = SOURCE + "/i_widget.fingerprint"
WIDGET_PY = SOURCE + "/i_widget.py"

# 封存模式唔會有網絡 timeout。
TIMEOUT = 5

# 本地快取大小上限。i_widget.py 正常只有十幾 KB，超過呢個數就當異常，
# 唔好俾一個損壞快取食晒 extension 嘅記憶體。
MAX_DOWNLOAD_BYTES = 256 * 1024

# 指紋格式（make_fingerprint.py：SHA256 前 16 個 hex 字元）。
FINGERPRINT_LENGTH = 16
FINGERPRINT_PATTERN = re.compile(r"[0-9a-f]{%d}" % FINGERPRINT_LENGTH)

# 最低檢查間隔。防低電／多次 reload 撞埋一齊打 GitHub。
#
# 配合 widget 本身 30 分鐘一次嘅 reload，呢個窗口唔應該細過 reload 間隔 ——
# 否則每個新 sandbox 都會問一次 GitHub，等於完全冇節流作用。
CHECK_INTERVAL = 30 * 60

# iOS 嘅 reload 時間唔準，可能早幾秒；而檢查時間係喺網絡請求之後先記錄。
# 冇容差的話「準時 30 分鐘」嘅 reload 會差少少唔夠鐘，變成一個鐘先查一次。
CHECK_GRACE = 60

# 版本標記：顯示喺錯誤畫面。用戶一眼睇到就知行緊邊個版本，
# 唔使再靠估 — 空白畫面本身零資訊量。
LAUNCHER_VERSION = "1.8.0"
REMOTE_FP = None  # 遠端拉碼已封存，永遠唔會填入


# ==========================================================================
# 足跡（trace）：真機除錯用
# ==========================================================================
#
# 綠色 default template = process 死咗或者 show_widget() 冇叫到，冇任何錯誤訊息。
# try/except 捉唔到硬崩潰、被系統殺（記憶體／超時），所以每過一個關卡就即刻
# 寫一行去 userkeys。下次喺 Pyto 入面讀 userkeys 嘅 i_widget.trace 就睇到「最後去到邊」。
TRACE_KEY = "i_widget.trace"
TRACE_MAX_LINES = 60
_T0 = time.time()
_trace_lines = []


def _crumb(step):
    """記低一個關卡（連同距離開始嘅秒數）。本身絕不會 raise。"""
    try:
        _trace_lines.append(f"{time.time() - _T0:6.2f}s {step}")
        del _trace_lines[:-TRACE_MAX_LINES]
        import userkeys

        userkeys.set("\n".join(_trace_lines), TRACE_KEY)
    except BaseException:
        pass


try:
    import userkeys as _uk

    _prev = ""
    try:
        _prev = _uk.get(TRACE_KEY) or ""
    except BaseException:
        _prev = ""
    # 保留上一次最後 15 行，用 ==== 分隔，咁就睇到「上一輪死喺邊」。
    _trace_lines.extend(_prev.splitlines()[-15:])
    _trace_lines.append("==== 新一輪 launcher " + time.strftime("%H:%M:%S"))
except BaseException:
    pass
_crumb(f"1 module 開始 v{LAUNCHER_VERSION}")


# ==========================================================================
# Pyto 官方 bug 修補：Color.dynamic() 一定會擲 TypeError
# ==========================================================================
#
# Pyto 原始碼（Lib/widgets.py）：
#
#     @classmethod
#     def dynamic(cls, light: Color, dark: Color) -> Color:
#         check(light, "light", Color)      # ← 傳 class，唔係 list
#         check(dark,  "dark",  Color)
#         return cls(__PyColor__.colorWithLight(
#             light.__py_color__, dark=dark.__py_color__))
#
# 而 `check` 內部做 `for t in expected:`。傳入 class（type object）會：
#
#     TypeError: 'type' object is not iterable
#
# 呢個係 **Pyto 自己嘅 bug**，2026-10-22 真機 probe 實測確認：
#
#     3 建構 Color/Font/Text → ERR TypeError: 'type' object is not iterable
#
# 影響範圍：**任何** 叫 `Color.dynamic()` 嘅代碼。Widget 冇 dynamic 色
# 就冇 light/dark 適應，但至少唔會死。
#
# 修法：自己實作 dynamic，繞過壞掉嘅 check()。
def _patch_color_dynamic():
    try:
        white = wd.Color.rgb(1.0, 1.0, 1.0)
        black = wd.Color.rgb(0.0, 0.0, 0.0)
    except BaseException:
        return
    try:
        wd.Color.dynamic(light=white, dark=black)
        return                      # 呢個 Pyto 版本冇 bug
    except BaseException:
        pass                        # 有 bug，繼續 patch
    try:
        from widgets import Color, __PyColor__

        def _dynamic(light, dark):
            return Color(__PyColor__.colorWithLight(
                light.__py_color__, dark=dark.__py_color__))

        Color.dynamic = staticmethod(_dynamic)
    except BaseException:
        pass


_patch_color_dynamic()
_crumb("2 patch_color_dynamic 完")


def _dyn(light, dark):
    """``Color.dynamic`` 安全版：patch 都唔成功就退返深色色。"""
    try:
        return wd.Color.dynamic(light=light, dark=dark)
    except BaseException:
        return dark


def _try(fn, fallback=None):
    """執行 ``fn()``；任何例外都唔會向上傳，回傳 ``fallback``。

    只可以用喺「顯示錯誤畫面」嘅路徑 —— 呢個函式存在係為咗
    保證最後防線自己都唔會爆。
    """
    try:
        return fn()
    except Exception:
        return fallback


def _text(value, font=None, color=None):
    """砌一個 `wd.Text`，任何選項出事都退回最基本嘅呼叫。"""
    kwargs = {}
    if font is not None:
        kwargs["font"] = font
    if color is not None:
        kwargs["color"] = color
    return _try(lambda: wd.Text(value, **kwargs), _try(lambda: wd.Text(value), None))

# 快取 key（存喺 Pyto 官方 userkeys = NSUserDefaults suite "group.pyto"，
# extension 同主 app 共用，唔會被 iOS 清理）。
KEY_CODE = "i_widget.cached_code"
KEY_FINGERPRINT = "i_widget.cached_fingerprint"
KEY_CHECKED = "i_widget.last_checked"

# 後備儲存：檔案。擺喺 launcher 同一層，方便人手檢查／刪除。
# 冇 userkeys（例如舊版 Pyto）或者寫入被拒，就 fallback 呢度。
#
# ⚠️ `__file__` 喺 Pyto Run Script **可能完全冇定義**。
#    如果喺 module level 直接用 `__file__`，會拋 NameError
#    → 成個 module import 失敗 → show_widget() 永遠唔會被叫
#    → home screen 顯示綠色 default template。
#    呢個正係 2026-10-22 真機實測遇到嘅 bug。
#
# 所以呢度全部用 getattr 兜底，並且提供多個 fallback 目錄。
def _cache_dir():
    # 1. __file__ 存在 → 同一層
    try:
        return os.path.dirname(os.path.abspath(__file__))
    except NameError:
        pass
    # 2. Pyto 常用暫存目錄
    for path in ("/tmp", os.path.expanduser("~"), os.getcwd()):
        try:
            if os.path.isdir(path):
                return path
        except BaseException:
            continue
    # 3. 最後：相對 "." （寫入會失敗，但至少 import 唔會死）
    return "."


CACHE_DIR = _cache_dir()
_crumb(f"3 cache_dir={CACHE_DIR}")
CACHED_PY = os.path.join(CACHE_DIR, "i_widget.cached.py")
CACHED_FP = os.path.join(CACHE_DIR, "i_widget.cached.fingerprint")
CACHED_CHECKED = os.path.join(CACHE_DIR, "i_widget.last_checked")

# userkeys 係 JSON 字典，太大會唔穩陣。超過呢個大小就淨係用檔案。
MAX_USERKEYS_BYTES = 100 * 1024


# --- 儲存層 -------------------------------------------------------------
# 兩種儲存，userkeys 優先（官方、extension 同 app 共用、唔會被清理），
# 檔案後備。兩者都失敗都唔會 crash —— 封存模式唔會改行遠端落載。


def _userkeys():
    try:
        import userkeys

        return userkeys
    except Exception:
        return None


def _keys_get(key):
    """讀 userkeys。回傳 None 代表「冇記錄或者讀唔到」。

    只在真係冇記錄時先返回 None；成功讀到 0 或者空字串都照樣返回。
    我們只會存 str / float，所以 None 唔會同有效值撞。
    """
    keys = _userkeys()
    if keys is None:
        return None
    try:
        return keys.get(key)
    except Exception:
        # KeyError = 冇呢個 key；其他 = userkeys 壞咗。都當冇記錄。
        return None


def load_code():
    """讀取同驗證一組本地快取（程式碼＋指紋）。userkeys → 檔案 → None。

    封存模式唔會再落載替代品。任何後備快取缺指紋、指紋格式錯、內容
    雜湊唔相符、語法錯或者 sanity marker 唔存在，都只會被丟棄。
    """
    code = _keys_get(KEY_CODE)
    fingerprint = _keys_get(KEY_FINGERPRINT)
    if code and _code_is_usable(code, "userkeys", fingerprint):
        return code

    code = _read(CACHED_PY, strip=False)
    fingerprint = _read(CACHED_FP)
    if code and _code_is_usable(code, "檔案", fingerprint):
        return code

    return None


# 快取必須包含嘅 sanity marker。冇咗就係舊／壞版本，丟掉。
#
# 點解唔淨係靠 compile()？因為 syntax 完全合法嘅舊版本（例如裸讀
# `wd.COLOR_SECONDARY_LABEL` 嘅早期版）一樣會令 widget 死，但 compile 過得到。
# 每次改動 i_widget.py 嘅結構時，要同步 bump 呢個數字，令所有舊快取
# 自動失效 —— 唔使再靠用戶手動刪 widget。
CACHE_MARKER = "I_WIDGET_API_2"


def _normalise_fingerprint(value):
    """回傳合法嘅 16 位 hex 指紋；缺少／格式錯就回傳 None。"""
    if not isinstance(value, str):
        return None
    value = value.strip()
    return value if FINGERPRINT_PATTERN.fullmatch(value) else None


def _code_is_usable(code, source, fingerprint=None):
    """快取程式碼係咪可信。

    Fail-closed 四重檢查，任何一項唔過都唔可以 exec：
      1. 內容大小正常
      2. 已存指紋格式合法，而且同內容 SHA256 前綴相符
      3. 語法通過 `compile()`
      4. 含有 `CACHE_MARKER`（即係新架構嘅版本，唔係舊殘留）
    """
    try:
        if not isinstance(code, str) or len(code) < 200:
            _log(f"{source} 快取太短或唔係文字，丟棄")
            return False
        if len(code.encode("utf-8")) > MAX_DOWNLOAD_BYTES:
            _log(f"{source} 快取超過 {MAX_DOWNLOAD_BYTES} bytes，丟棄")
            return False

        expected = _normalise_fingerprint(fingerprint)
        if expected is None:
            _log(f"{source} 快取指紋缺少或格式錯，丟棄")
            return False
        if fingerprint_of(code) != expected:
            _log(f"{source} 快取指紋同內容對唔上，丟棄")
            return False

        compile(code, WIDGET_PY, "exec")

        if CACHE_MARKER not in code:
            _log(f"{source} 快取冇 {CACHE_MARKER} marker（舊版本），丟棄")
            return False

        return True
    except SyntaxError as error:
        _log(f"{source} 快取語法錯（{error}），丟棄")
        return False
    except Exception as error:
        _log(f"{source} 快取驗證失敗（{type(error).__name__}），丟棄")
        return False


def load_fingerprint():
    value = _keys_get(KEY_FINGERPRINT)
    if value:
        return _normalise_fingerprint(value)
    return _normalise_fingerprint(_read(CACHED_FP))


def load_checked():
    """上次檢查更新嘅時間（unix timestamp）。"""
    value = _keys_get(KEY_CHECKED)
    if value is not None:
        try:
            return float(value)
        except (TypeError, ValueError):
            return 0.0
    try:
        return float(_read(CACHED_CHECKED) or 0)
    except (TypeError, ValueError):
        return 0.0


def save(code, fingerprint, checked):
    """一次過寫晒三樣。返回 True 代表至少有一個後端成功。

    封存模式只接受已經通過指紋、語法同 sanity 驗證嘅快取。驗證失敗
    就唔會寫入任何後端，避免製造出一個下次有機會用到嘅未驗證快取。
    """
    if not _code_is_usable(code, "新快取", fingerprint):
        return False

    stored = False

    keys = _userkeys()
    if keys is not None:
        try:
            if len(code.encode("utf-8")) <= MAX_USERKEYS_BYTES:
                keys.set(code, KEY_CODE)
                keys.set(fingerprint, KEY_FINGERPRINT)
            else:
                # 太大放唔落 userkeys：清走舊版本，否則 load_code() 會
                # 讀返 userkeys 入面嘅舊程式碼，同檔案嘅新指紋夾硬配對。
                for key in (KEY_CODE, KEY_FINGERPRINT):
                    try:
                        keys.delete(key)
                    except KeyError:
                        pass
            keys.set(checked, KEY_CHECKED)
            stored = True
        except Exception as error:
            _log(f"userkeys 寫入失敗，改用檔案：{error}")

    if _write(CACHED_PY, code):
        _write(CACHED_FP, fingerprint)
        _write(CACHED_CHECKED, str(checked))
        stored = True

    if not stored:
        _log("警告：userkeys 同檔案都寫唔到，本地快取可能唔可用")
    else:
        _yield_after_write()
    return stored


def touch_checked(checked):
    """淨係更新檢查時間（例如：遠端冇新版本，但仍然問過）。"""
    keys = _userkeys()
    if keys is not None:
        try:
            keys.set(checked, KEY_CHECKED)
        except Exception:
            pass
    _write(CACHED_CHECKED, str(checked))
    _yield_after_write()


def clear_cache():
    keys = _userkeys()
    if keys is not None:
        for key in (KEY_CODE, KEY_FINGERPRINT, KEY_CHECKED):
            try:
                keys.delete(key)
            except Exception:
                pass
    for path in (CACHED_PY, CACHED_FP, CACHED_CHECKED):
        try:
            os.remove(path)
        except OSError:
            pass


# --- 工具 ---------------------------------------------------------------

# iOS 27 會把「寫入之後即刻要求 render」合併成同一次執行，結果 widget 顯示的
# 係寫入之前嘅狀態。Apple 建議寫入之後 yield 一下，等 file coordinator 發佈。
# 0.2 秒對一個 30 分鐘 reload 嘅 widget 完唔構成成本。
COALESCE_DELAY = 0.2


def _yield_after_write():
    """寫入持久層之後叫一次，令系統有機會讀到新值。"""
    if not COALESCE_DELAY:
        return
    try:
        from time import sleep

        sleep(COALESCE_DELAY)
    except Exception:
        pass


def _log(message):
    """Extension 入面 print 可能唔見得，寫去 console 都係有的。"""
    try:
        print(f"[i-widget] {message}")
    except Exception:
        pass


def _read(path, strip=True):
    try:
        # newline="" 保留原本換行；快取指紋係對完整內容計算，唔可以正規化。
        with open(path, encoding="utf-8", newline="") as handle:
            value = handle.read()
        return value.strip() if strip else value
    except Exception:
        return None


def _write(path, text):
    try:
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(text)
        return True
    except Exception:
        return False


def _fetch(url):
    """遠端拉碼已封存：呢個函式永遠唔會發出網絡請求。"""
    _log(f"遠端拉碼已封存，拒絕下載 {url}")
    return None


def fingerprint_of(code):
    """同 make_fingerprint.py 一樣嘅算法。

    hashlib 喺函式入面先 import：module level 一旦 import 失敗，成個 launcher
    就死喺 show_widget() 之前（綠色）。真機從來未量度過 hashlib 係咪可用。
    """
    import hashlib

    return hashlib.sha256(code.encode("utf-8")).hexdigest()[:FINGERPRINT_LENGTH]


def _should_check():
    """舊更新節流介面；遠端拉碼封存後永遠唔需要檢查更新。"""
    return False


# --- 更新邏輯 -----------------------------------------------------------

def _try_update():
    """遠端更新入口保留作相容介面，但封存後永遠唔做任何事。"""
    _log("Pyto 遠端拉碼已封存；不下載指紋或程式碼")
    _crumb("4a 遠端拉碼已封存，跳過更新")
    return False


def _load_code():
    """只載入通過驗證嘅本地快取；冇可信快取就回傳 None。"""
    _crumb("4 遠端拉碼已封存")
    try:
        _try_update()
    except Exception as error:
        _log(f"封存更新介面出錯，改用本地快取：{error}")
        _crumb(f"4x _try_update 爆 {type(error).__name__}: {error}")
    _crumb("5 讀取並驗證本地快取")

    code = load_code()
    if code:
        _crumb(f"6 用可信快取 {len(code)} bytes")
        return code, "cache"

    _crumb("6 冇可信本地快取；唔會改行遠端下載")
    return None, None


# --- 萬一連程式碼都攞唔到 -----------------------------------------------

def _show_offline_widget(reason, title="更新失敗", detail=None):
    """顯示一個講明情況嘅 widget，唔好留空白。

    ``detail`` 係額外一行細字（例如錯誤訊息），方便喺 home screen 直接睇到原因。

    ⚠️ 呢個函式係「最後防線」——連佢都爆就一樣得綠色 default template。
    所以呢度**完全唔准**用 `wd.COLOR_*` 裸讀或者任何可能不存在嘅 API：
    缺色就 fallback 去 `Color.dynamic`，缺 font 就 fallback 去無 font。
    """
    try:
        # --- 防禦性取色：任何一個常數缺失都唔會炸 ---------------------
        # 用 _dyn() 而唔係直接 Color.dynamic：喺部分 Pyto 版本
        # 會擲 TypeError（見上面 _patch_color_dynamic 註解）。
        bg = _try(lambda: _dyn(
            wd.Color.rgb(1.0, 1.0, 1.0),
            wd.Color.rgb(0.11, 0.11, 0.118),
        ), None)
        fg = _try(lambda: _dyn(
            wd.Color.rgb(0.0, 0.0, 0.0),
            wd.Color.rgb(1.0, 1.0, 1.0),
        ), None)
        muted = _try(lambda: getattr(wd, "COLOR_SECONDARY_LABEL"), fg)

        def _font(size, bold=False):
            """font API 唔存在就唔傳 font —— 寧願用系統預設字型都要見到字。"""
            name = "bold_system_font_of_size" if bold else "system_font_of_size"
            return _try(lambda: getattr(wd.Font, name)(size), None)

        # ⚠️ 呢行一定要喺 try 入面最前面：如果 `wd.Widget()` 本身就擲錯，
        # except 分支會用到未綁定嘅 `widget` → NameError → 綠色。
        widget = wd.Widget()
        if bg is not None:
            _try(lambda: setattr(widget, "background_color", bg), None)

        for layout in (
            getattr(widget, "small_layout", None),
            getattr(widget, "medium_layout", None),
            getattr(widget, "large_layout", None),
            getattr(widget, "extra_large_layout", None),
        ):
            # ⚠️ 唔可以裸讀任何 layout：2026-10-22 真機教訓。
            # 原本 `widget.extra_large_layout` 一旦缺失就 AttributeError，
            # 跌入 except 之後再裸讀 small_layout / large_layout →
            # **再死一次** → 綠色 default template（死亡螺旋）。
            # 兩個 layout 都缺，先算真係冇出路。
            if layout is None:
                continue
            _try(lambda: layout.add_vertical_spacer(), None)
            # 版本標記：空白畫面零資訊量，一定要令用戶一眼睇到行緊邊個版本。
            _try(lambda: layout.add_row([_text("i-widget",
                                              font=_font(20, bold=True), color=fg)]), None)
            _try(lambda: layout.add_row([_text(f"{LAUNCHER_VERSION} · 遠端拉碼已封存",
                                              font=_font(11), color=muted)]), None)
            _try(lambda: layout.add_row([_text(title, font=_font(13), color=muted)]), None)
            if detail:
                _try(lambda: layout.add_row([_text(detail, font=_font(10), color=muted)]), None)
            _try(lambda: layout.add_vertical_spacer(), None)

        _try(lambda: wd.schedule_next_reload(timedelta(minutes=30)), None)
        _crumb(f"9 離線畫面 show_widget：{reason}")
        wd.show_widget(widget)
        _log(f"已顯示離線 widget：{reason}")
    except Exception as error:
        _log(f"連離線 widget 都顯示唔到：{type(error).__name__}: {error}")
        # 最後一搏：極簡畫面，淨係用最低風險嘅 API。
        # ⚠️ 重新起一個 `wd.Widget()`（上面 try 嗰個未必成功綁定）。
        # 同樣唔可以裸讀 layout：逐個試，就算得一個都照畫。
        try:
            widget = wd.Widget()
        except Exception:
            return
        for name in ("small_layout", "medium_layout", "large_layout"):
            try:
                layout = getattr(widget, name, None)
                if layout is None:
                    continue
                layout.add_vertical_spacer()
                layout.add_row([wd.Text("i-widget 執行失敗")])
                layout.add_row([wd.Text(f"{LAUNCHER_VERSION} · {reason}")])
                layout.add_vertical_spacer()
                wd.show_widget(widget)
                return                      # 成功就收工，唔好再試
            except Exception:
                continue


# --- 入口 ---------------------------------------------------------------

def main():
    # ⚠️ 最外層防線。
    # 之前 _load_code() 同 main() 都冇 try 住自己：任何未預見嘅 exception
    # （userkeys 怪手勢、檔案 I/O、import 失敗…）都會令成個 script 死喺度，
    # `_show_offline_widget()` 永遠唔會被叫 → iOS 顯示綠色 default template。
    # 呢個 try 保證「只要仲有命，就一定見到畫面」。
    try:
        code, origin = _load_code()
    except Exception as error:
        _log(f"_load_code 爆：{type(error).__name__}: {error}")
        _show_offline_widget(
            "本地快取載入／驗證失敗",
            title="Pyto 遠端拉碼已封存",
            detail=f"{type(error).__name__}: {error}"[:140],
        )
        return

    if not code:
        _show_offline_widget(
            "遠端拉碼已封存，而且冇通過驗證嘅本地快取",
            title="Pyto 遠端拉碼已封存",
            detail="本地快取驗證失敗（指紋／語法／sanity）；請改用本機 i_widget.py",
        )
        return

    # `_load_code()` 已經核對過已存指紋、語法同 sanity marker。呢度再
    # compile 只係最後防線，絕唔係取而代之嘅驗證。
    try:
        compiled = compile(code, "i_widget.py", "exec")
    except SyntaxError as error:
        _log(f"快取語法錯（{error}），退回封存錯誤畫面")
        _show_offline_widget(
            "本地快取驗證失敗",
            title="Pyto 遠端拉碼已封存",
            detail=f"快取語法錯：{error}"[:140],
        )
        return

    _log(f"執行中（來源：{origin}）")
    _crumb(f"7 即將 exec（來源 {origin}）")
    # ⚠️ `__file__` 喺 Pyto Run Script 可能冇定義。
    #    直接喺呢度寫 `__file__` 會喺 exec 前就 NameError。
    #    用 globals().get() 兜底；widget 本身唔會靠 __file__ 運作。
    _widget_globals = {"__name__": "__main__", "__file__": CACHED_PY}
    try:
        exec(compiled, _widget_globals)
        _crumb("8 exec 完，無例外")
    except BaseException as error:
        _crumb(f"8x exec 爆 {type(error).__name__}: {error}")
        # BaseException：連 SystemExit / KeyboardInterrupt 都捉埋，
        # 因為呢度寧願畫錯都唔好畫唔到。
        # 以前 widget 程式一爆錯，home screen 就一片空白，完全睇唔到原因。
        # 而家將錯誤顯示出嚟，下次 reload 會再試。
        _log(f"widget 執行出錯：{type(error).__name__}: {error}")
        _show_offline_widget(
            "widget 執行出錯",
            title="執行出錯",
            detail=f"{type(error).__name__}: {error}"[:140],
        )


# 最後一道：連 main() 本身都爆，都要嘗試講返啲嘢。
try:
    main()
except BaseException as _fatal:
    try:
        print(f"[i-widget] FATAL in main(): {type(_fatal).__name__}: {_fatal}")
    except Exception:
        pass
    try:
        _show_offline_widget(
            "launcher 嚴重錯誤",
            title="嚴重錯誤",
            detail=f"{type(_fatal).__name__}: {_fatal}"[:140],
        )
    except BaseException:
        pass