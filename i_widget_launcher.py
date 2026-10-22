"""i-widget 自更新啟動器 —— 從 GitHub 拉最新版 i_widget.py 執行。

設計重點（按 iOS WidgetKit extension 的實際限制而訂）：

* **Extension 有 RAM 上限**，所以唔可以每次都重新 parse 一個大檔再 exec。
  做法係：先只下載一個極小的「版本指紋」檔，確認同本地快取唔同先
  真正下載完整程式碼。15 分鐘 reload 一次之下，網絡用量近乎零。
* **網絡可能失敗**（飛機模式、GitHub 故障、限流）。任何一步失敗就
  靜靜行本地快取，widget 照樣出畫面，唔會變空白。
* **最新嘅程式碼可能有 bug**。所以先下載、再做語法檢查（compile），
  通過才覆寫快取並執行；語法錯就繼續行舊快取。呢個令「推壞咗去 main」
  唔會即刻炸你個 home screen。
* **時間預算**：WidgetKit 每次 reload 給嘅時間有限，所以所有網絡請求
  都設短 timeout，抓唔到就當冇更新。

用法：呢個檔案就係 widget 指向嘅 script（取代直接指向 i_widget.py）。
"""

import os
import time
from datetime import timedelta

import widgets as wd

# --- 設定 ---------------------------------------------------------------

SOURCE = "https://raw.githubusercontent.com/iceninye/I-widget/main"
FINGERPRINT = SOURCE + "/i_widget.fingerprint"
WIDGET_PY = SOURCE + "/i_widget.py"

# Extension 記憶體緊，timeout 要短。抓唔到就當今次冇更新。
TIMEOUT = 8

# 最低檢查間隔。防低電／多次 reload 撞埋一齊打 GitHub。
#
# 配合 widget 本身 30 分鐘一次嘅 reload，呢個窗口唔應該細過 reload 間隔 ——
# 否則每個新 sandbox 都會問一次 GitHub，等於完全冇節流作用。
CHECK_INTERVAL = 30 * 60

# 快取 key（存喺 Pyto 官方 userkeys = NSUserDefaults suite "group.pyto"，
# extension 同主 app 共用，唔會被 iOS 清理）。
KEY_CODE = "i_widget.cached_code"
KEY_FINGERPRINT = "i_widget.cached_fingerprint"
KEY_CHECKED = "i_widget.last_checked"

# 後備儲存：檔案。擺喺 launcher 同一層，方便人手檢查／刪除。
# 冇 userkeys（例如舊版 Pyto）或者寫入被拒，就 fallback 呢度。
CACHE_DIR = os.path.dirname(os.path.abspath(__file__))
CACHED_PY = os.path.join(CACHE_DIR, "i_widget.cached.py")
CACHED_FP = os.path.join(CACHE_DIR, "i_widget.cached.fingerprint")
CACHED_CHECKED = os.path.join(CACHE_DIR, "i_widget.last_checked")

# userkeys 係 JSON 字典，太大會唔穩陣。超過呢個大小就淨係用檔案。
MAX_USERKEYS_BYTES = 100 * 1024


# --- 儲存層 -------------------------------------------------------------
# 兩種儲存，userkeys 優先（官方、extension 同 app 共用、唔會被清理），
# 檔案後備。兩者都失敗都唔會 crash —— 寧願每次重新落載。


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
    """讀快取程式碼。userkeys → 檔案 → None。"""
    code = _keys_get(KEY_CODE)
    if code:
        return code
    return _read(CACHED_PY)


def load_fingerprint():
    value = _keys_get(KEY_FINGERPRINT)
    if value:
        return value
    return _read(CACHED_FP)


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

    兩者都失敗唔會 raise —— 寧願下次重新落載，都唔好令 widget 死掉。
    """
    stored = False

    keys = _userkeys()
    if keys is not None:
        try:
            if len(code.encode("utf-8")) <= MAX_USERKEYS_BYTES:
                keys.set(code, KEY_CODE)
                keys.set(fingerprint, KEY_FINGERPRINT)
            keys.set(checked, KEY_CHECKED)
            stored = True
        except Exception as error:
            _log(f"userkeys 寫入失敗，改用檔案：{error}")

    if _write(CACHED_PY, code):
        _write(CACHED_FP, fingerprint)
        _write(CACHED_CHECKED, str(checked))
        stored = True

    if not stored:
        _log("警告：userkeys 同檔案都寫唔到，下次會重新落載")
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


def _read(path):
    try:
        with open(path, encoding="utf-8") as handle:
            return handle.read().strip()
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
    """下載一段文字。失敗回傳 None（唔會 raise）。"""
    try:
        from urllib.request import urlopen

        with urlopen(url, timeout=TIMEOUT) as response:
            return response.read().decode("utf-8")
    except Exception as error:
        _log(f"取唔到 {url}：{error}")
        return None


def _should_check():
    """上次檢查過就唔好即刻再打網絡。"""
    checked = load_checked()
    if not checked:
        return True  # 冇記錄 = 即刻查一次
    return (time.time() - checked) > CHECK_INTERVAL


# --- 更新邏輯 -----------------------------------------------------------

def _try_update():
    """嘗試拉新版。成功返回 True；任何一步失敗都返回 False。"""
    if not _should_check():
        return False

    remote_fp = _fetch(FINGERPRINT)
    if remote_fp is None:
        return False

    if remote_fp == load_fingerprint():
        _log("已經係最新版")
        touch_checked(time.time())  # 問過咗，唔使十秒後再問
        return False

    _log(f"發現新版 {remote_fp}，落載中")
    code = _fetch(WIDGET_PY)
    if not code or len(code) < 200:
        _log("程式碼下載失敗或太短，維持舊快取")
        touch_checked(time.time())
        return False

    # 語法檢查：壞咗的 commit 唔好污染快取。
    try:
        compile(code, WIDGET_PY, "exec")
    except SyntaxError as error:
        _log(f"新版本語法錯（{error}），維持舊快取")
        # 指紋刻意唔更新 → 等你修好再 push，下次 reload 會自動再試。
        # 但要更新檢查時間，否則每次 reload 都撲去 GitHub 撞同一個壞版本。
        touch_checked(time.time())
        return False

    save(code, remote_fp, time.time())
    _log("已更新到本地快取")
    return True


def _load_code():
    """決定今次行邊份程式碼。永遠唔會回傳 None 除非真係咩都冇。"""
    try:
        _try_update()
    except Exception as error:
        _log(f"更新過程出錯，繼續用快取：{error}")

    code = load_code()
    if code:
        return code, "cache"

    # 連快取都冇（例如第一次執行）→ 直接拉一次，順手寫入快取。
    code = _fetch(WIDGET_PY)
    if code and len(code) >= 200:
        try:
            compile(code, WIDGET_PY, "exec")
        except SyntaxError:
            return None, None
        save(code, "unverified", time.time())
        return code, "remote"

    return None, None


# --- 萬一連程式碼都攞唔到 -----------------------------------------------

def _show_offline_widget(reason):
    """完全冇程式碼可用時，顯示一個講明情況嘅 widget，唔好留空白。"""
    try:
        widget = wd.Widget()
        for layout in (
            widget.small_layout,
            widget.medium_layout,
            widget.large_layout,
            widget.extra_large_layout,
        ):
            layout.add_vertical_spacer()
            layout.add_row([wd.Text("i-widget", font=wd.Font.bold_system_font_of_size(20))])
            layout.add_row([
                wd.Text("更新失敗", font=wd.Font.system_font_of_size(13), color=wd.COLOR_SECONDARY_LABEL),
            ])
            layout.add_vertical_spacer()

        wd.schedule_next_reload(timedelta(minutes=30))
        wd.show_widget(widget)
        _log(f"已顯示離線 widget：{reason}")
    except Exception as error:
        _log(f"連離線 widget 都顯示唔到：{error}")


# --- 入口 ---------------------------------------------------------------

def main():
    code, origin = _load_code()

    if not code:
        _show_offline_widget("攞唔到任何程式碼")
        return

    # exec 之前再 compile 一次：cache 檔可能已經被手動改壞。
    try:
        compiled = compile(code, "i_widget.py", "exec")
    except SyntaxError as error:
        _log(f"快取語法錯（{error}），退回離線畫面")
        _show_offline_widget("快取已損壞")
        return

    _log(f"執行中（來源：{origin}）")
    exec(compiled, {"__name__": "__main__", "__file__": __file__})


main()