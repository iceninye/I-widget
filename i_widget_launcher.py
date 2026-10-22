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

# 快取放喺 Pyto 自己嘅目錄（同 widget script 同一層），唔會被 iOS 清理。
CACHE_DIR = os.path.dirname(os.path.abspath(__file__))
CACHED_PY = os.path.join(CACHE_DIR, "i_widget.cached.py")
CACHED_FP = os.path.join(CACHE_DIR, "i_widget.cached.fingerprint")

# 最低檢查間隔。防低電／多次 reload 撞埋一齊打 GitHub。
CHECK_INTERVAL = 10 * 60


# --- 工具 ---------------------------------------------------------------

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
    """用快取指紋檔的 mtime 做節流，避免每次 reload 都打網絡。"""
    try:
        age = time.time() - os.path.getmtime(CACHED_FP)
        return age > CHECK_INTERVAL
    except Exception:
        return True  # 冇快取 = 即刻查一次


# --- 更新邏輯 -----------------------------------------------------------

def _try_update():
    """嘗試拉新版。成功返回 True；任何一步失敗都返回 False。"""
    if not _should_check():
        return False

    remote_fp = _fetch(FINGERPRINT)
    if remote_fp is None:
        return False

    local_fp = _read(CACHED_FP)
    if local_fp == remote_fp:
        _log("已經係最新版")
        # 節流：順手 refresh mtime
        _write(CACHED_FP, remote_fp)
        return False

    _log(f"發現新版 {remote_fp}，落載中")
    code = _fetch(WIDGET_PY)
    if not code or len(code) < 200:
        _log("程式碼下載失敗或太短，維持舊快取")
        return False

    # 語法檢查：壞咗的 commit 唔好污染快取。
    try:
        compile(code, WIDGET_PY, "exec")
    except SyntaxError as error:
        _log(f"新版本語法錯（{error}），維持舊快取")
        return False

    if not _write(CACHED_PY, code):
        return False
    _write(CACHED_FP, remote_fp)
    _log("已更新到本地快取")
    return True


def _load_code():
    """決定今次行邊份程式碼。永遠唔會回傳 None 除非真係咩都冇。"""
    try:
        _try_update()
    except Exception as error:
        _log(f"更新過程出錯，繼續用快取：{error}")

    code = _read(CACHED_PY)
    if code:
        return code, "cache"

    # 連快取都冇（例如第一次執行）→ 直接拉一次，唔寫檔。
    code = _fetch(WIDGET_PY)
    if code and len(code) >= 200:
        try:
            compile(code, WIDGET_PY, "exec")
        except SyntaxError:
            code = None
    return code, "remote"


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

        wd.schedule_next_reload(timedelta(minutes=15))
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