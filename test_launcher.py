"""i-widget launcher 封存後回歸測試：只執行已驗證本地快取，永不遠端拉碼。"""
import hashlib
import os
import shutil
import socket
import sys
import tempfile
from datetime import timedelta
from pathlib import Path
from unittest.mock import patch

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from mock_pyto import RELOADS, SHOWN, UK_STATE, UK_STORE, text_of  # noqa: E402

LAUNCHER = os.path.join(HERE, "i_widget_launcher.py")
with open(LAUNCHER, encoding="utf-8") as handle:
    LAUNCHER_SRC = handle.read()

GOOD = '''import widgets as wd
VERSION = "v1"
I_WIDGET_API_2 = True
widget = wd.Widget()
for layout in (widget.small_layout, widget.medium_layout, widget.large_layout, widget.extra_large_layout):
    layout.add_row([wd.Text("version v1")])
wd.schedule_next_reload(__import__("datetime").timedelta(minutes=15))
wd.show_widget(widget)
'''
GOOD_V2 = GOOD.replace("v1", "v2")
BROKEN = "# " + ("padding line to exceed the minimum size guard. " * 4) + "\ndef broken(:\n    pass\n"
STALE = GOOD.replace("I_WIDGET_API_2 = True\n", "")
BOOM = GOOD.replace('VERSION = "v1"', 'VERSION = "v1"\nraise RuntimeError("boom 測試")')

PASS, FAIL = [], []
TEMP_DIRS = []


def fingerprint(code):
    return hashlib.sha256(code.encode("utf-8")).hexdigest()[:16]


def check(name, condition, detail=""):
    (PASS if condition else FAIL).append(name)
    print(f"  {'✓' if condition else '✗ FAIL'}  {name}{(' → ' + detail) if detail and not condition else ''}")


def texts(widget):
    if widget is None:
        return []
    return [str(text_of(component)) for row in widget.small_layout.rows
            if isinstance(row, list) for component in row if hasattr(component, "_Component__args")]


def run_launcher(code=None, saved_fingerprint=None, file_code=None, file_fingerprint=None,
                 no_file=False, broken_userkeys=False):
    directory = tempfile.mkdtemp(prefix="iw-launcher-test-")
    TEMP_DIRS.append(directory)
    shutil.copyfile(LAUNCHER, os.path.join(directory, "i_widget_launcher.py"))
    if code is not None:
        UK_STORE["i_widget.cached_code"] = code
    if saved_fingerprint is not None:
        UK_STORE["i_widget.cached_fingerprint"] = saved_fingerprint
    if file_code is not None:
        with open(os.path.join(directory, "i_widget.cached.py"), "w", encoding="utf-8", newline="") as handle:
            handle.write(file_code)
    if file_fingerprint is not None:
        with open(os.path.join(directory, "i_widget.cached.fingerprint"), "w", encoding="utf-8") as handle:
            handle.write(file_fingerprint)

    SHOWN.clear()
    RELOADS.clear()
    UK_STORE.clear() if not (code is not None or saved_fingerprint is not None) else None
    # 重新放回 userkeys 快取：清空係用嚟移除前一輪 trace，而唔係刪今次輸入。
    if code is not None:
        UK_STORE["i_widget.cached_code"] = code
    if saved_fingerprint is not None:
        UK_STORE["i_widget.cached_fingerprint"] = saved_fingerprint
    UK_STATE["broken"] = broken_userkeys
    globals_ = {"__name__": "__main__"}
    if not no_file:
        globals_["__file__"] = os.path.join(directory, "i_widget_launcher.py")
    error = None
    try:
        if no_file:
            # 防止測試機 /tmp 或 home 既有快照令「無 __file__」情境偶然通過。
            with patch("os.path.isdir", return_value=False):
                exec(compile(LAUNCHER_SRC, "launcher.py", "exec"), globals_)
        else:
            exec(compile(LAUNCHER_SRC, globals_["__file__"], "exec"), globals_)
    except Exception as exc:
        error = exc
    finally:
        UK_STATE["broken"] = False
    return SHOWN[0] if SHOWN else None, globals_, error, directory


def executed(widget):
    return "version v1" in texts(widget) or "version v2" in texts(widget)


print("\n【A】零快取：顯示封存畫面，不執行 code，亦不發出網絡請求")
network_calls = []
original_connection = socket.create_connection


def forbidden_connection(*args, **kwargs):
    network_calls.append((args, kwargs))
    raise AssertionError("封存 launcher 不准連線")


socket.create_connection = forbidden_connection
try:
    widget, namespace, error, _ = run_launcher()
finally:
    socket.create_connection = original_connection
check("A1 有畫面、無外拋錯誤", widget is not None and error is None, str(error))
check("A2 未執行任何快取 code", not executed(widget), str(texts(widget)))
check("A3 明示遠端拉碼已封存", any("遠端拉碼已封存" in text for text in texts(widget)))
check("A4 零網絡連線", network_calls == [], str(network_calls))
check("A5 _fetch 硬停用", namespace["_fetch"]("https://example.invalid") is None)
check("A6 _should_check 永遠 false", namespace["_should_check"]() is False)

print("\n【B】已驗證 userkeys 快取仍可離線執行")
widget, _, error, _ = run_launcher(GOOD, fingerprint(GOOD))
check("B1 執行 v1", "version v1" in texts(widget), str(texts(widget)))
check("B2 無外拋錯誤", error is None, str(error))

print("\n【C】已驗證檔案快取仍可離線執行（指紋檔容許換行）")
widget, _, error, _ = run_launcher(file_code=GOOD_V2, file_fingerprint=fingerprint(GOOD_V2) + "\n")
check("C1 執行 v2", "version v2" in texts(widget), str(texts(widget)))
check("C2 排程沿用 15 分鐘", RELOADS == [timedelta(minutes=15)], str(RELOADS))

print("\n【D】指紋缺少／格式錯／內容不符都必須 fail closed")
for label, code, fp in [
    ("缺少指紋", GOOD, None),
    ("格式錯", GOOD, "not-a-fingerprint"),
    ("大寫格式錯", GOOD, fingerprint(GOOD).upper()),
    ("內容不符", GOOD, fingerprint(GOOD_V2)),
]:
    widget, _, error, _ = run_launcher(code, fp)
    check(f"D {label} 不執行 code", not executed(widget), str(texts(widget)))
    check(f"D {label} 有封存畫面、無外拋錯誤", widget is not None and error is None, str(error))

print("\n【E】語法錯／缺 sanity marker／超大／過短快取都拒絕")
for label, code in [
    ("語法錯", BROKEN),
    ("缺 sanity marker", STALE),
    ("超大", "# " + "x" * (300 * 1024) + "\n" + GOOD),
    ("過短", "I_WIDGET_API_2 = True"),
]:
    widget, _, error, _ = run_launcher(code, fingerprint(code))
    check(f"E {label} 不執行 code", not executed(widget), str(texts(widget)))
    check(f"E {label} 有封存畫面、無外拋錯誤", widget is not None and error is None, str(error))

print("\n【F】壞 userkeys 後備到好檔案；不能跨後備夾錯指紋")
widget, _, error, _ = run_launcher(
    file_code=GOOD, file_fingerprint=fingerprint(GOOD), broken_userkeys=True
)
check("F1 userkeys 壞仍執行好檔案快取", "version v1" in texts(widget), str(texts(widget)))
check("F2 無外拋錯誤", error is None, str(error))
widget, _, error, _ = run_launcher(
    GOOD_V2, fingerprint(GOOD), file_code=GOOD, file_fingerprint=fingerprint(GOOD)
)
check("F3 好檔案可獨立驗證並執行", "version v1" in texts(widget), str(texts(widget)))

print("\n【G】換行必須保留；CRLF 內容要按原 bytes 驗證")
crlf = GOOD.replace("\n", "\r\n")
widget, _, error, _ = run_launcher(file_code=crlf, file_fingerprint=fingerprint(crlf))
check("G1 CRLF 快取指紋相符", "version v1" in texts(widget), str(texts(widget)))
widget, _, error, _ = run_launcher(file_code=crlf, file_fingerprint=fingerprint(GOOD))
check("G2 正規化後指紋不符必須拒絕", not executed(widget))

print("\n【H】save() 拒絕未驗證快取，而且不污染既有儲存")
UK_STORE["i_widget.cached_code"] = GOOD
UK_STORE["i_widget.cached_fingerprint"] = fingerprint(GOOD)
for label, code, fp in [
    ("指紋不符", GOOD_V2, fingerprint(GOOD)),
    ("語法錯", BROKEN, fingerprint(BROKEN)),
    ("缺 marker", STALE, fingerprint(STALE)),
]:
    widget, namespace, error, directory = run_launcher(GOOD, fingerprint(GOOD))
    check(f"H {label} save 拒絕", namespace["save"](code, fp, 1.0) is False)
    check(f"H {label} userkeys 未污染", UK_STORE["i_widget.cached_code"] == GOOD)
    cached_path = os.path.join(directory, "i_widget.cached.py")
    if os.path.exists(cached_path):
        with open(cached_path, encoding="utf-8", newline="") as handle:
            check(f"H {label} 檔案未污染", handle.read() == GOOD)
    else:
        check(f"H {label} 未建立未驗證檔案", True)

print("\n【I】執行錯誤有畫面；Pyto Run Script 無 __file__ 都唔可以 NameError")
widget, _, error, _ = run_launcher(BOOM, fingerprint(BOOM))
check("I1 執行錯誤不外拋", error is None, str(error))
check("I2 顯示 boom 錯誤", any("boom" in text for text in texts(widget)), str(texts(widget)))
widget, _, error, _ = run_launcher(GOOD, fingerprint(GOOD), no_file=True)
check("I3 無 __file__ 仍執行 userkeys 快取", "version v1" in texts(widget), str(texts(widget)))
check("I4 無外拋錯誤", error is None, str(error))
widget, _, error, _ = run_launcher(no_file=True)
check("I5 無 __file__ 且無快取仍有封存畫面", widget is not None and not executed(widget))

print("\n【J】真 i_widget.py 配合同一指紋可以本地執行")
import make_fingerprint  # noqa: E402
with open(os.path.join(HERE, "i_widget.py"), encoding="utf-8", newline="") as handle:
    real_code = handle.read()
real_fp = make_fingerprint.fingerprint(Path(HERE) / "i_widget.py")
check("J1 repo 指紋算法一致", real_fp == fingerprint(real_code), f"{real_fp} != {fingerprint(real_code)}")
widget, _, error, _ = run_launcher(real_code, real_fp)
check("J2 真 widget 有畫面、無外拋錯誤", widget is not None and error is None, str(error))
check("J3 不是封存錯誤畫面", not any("遠端拉碼已封存" in text for text in texts(widget)), str(texts(widget)))

print("\n【K】靜態保證與足跡")
check("K1 launcher 不含 urlopen", "urlopen" not in LAUNCHER_SRC)
check("K2 launcher 不含 urllib import", "import urllib" not in LAUNCHER_SRC)
check("K3 仍保留 coalescing 防護", "_yield_after_write()" in LAUNCHER_SRC)
check("K4 離線畫面仍為 30 分鐘", "timedelta(minutes=30)" in LAUNCHER_SRC)
widget, _, error, _ = run_launcher(GOOD, fingerprint(GOOD))
trace = UK_STORE.get("i_widget.trace", "")
check("K5 足跡記錄封存分支", "4a 遠端拉碼已封存" in trace, trace)
check("K6 足跡記錄驗證後 exec", "7 即將 exec" in trace and "8 exec 完" in trace, trace)

for directory in TEMP_DIRS:
    shutil.rmtree(directory, ignore_errors=True)
print("\n" + "=" * 60)
print(f"通過 {len(PASS)}  失敗 {len(FAIL)}")
if FAIL:
    print("失敗：")
    for name in FAIL:
        print("  -", name)
    sys.exit(1)
print("全部通過")
