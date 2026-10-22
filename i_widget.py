"""i-widget — iPhone Home Screen 嘅「時間／系統狀態」widget（Pyto 版本）。

用 Pyto 內置嘅 widgets API 寫成，唔需要 Mac 或 Xcode。
安裝步驟見 README.md。

版本 1.3.0
"""

VERSION = "1.3.0"
COMMIT = "32d4cdc"

# 快取世代標記：launcher 要求快取必須含有呢個 marker，
# 否則當作舊版本丟棄並重新落載（避免 outdated cache 鎖死 widget）。
I_WIDGET_API_2 = True

import os
import re
import time
from datetime import datetime, timedelta

import widgets as wd


def _patch_color_dynamic():
    """繞過 Pyto 19.0 嘅一個 bug。

    ``Color.dynamic()`` 內部叫 ``check(light, "light", Color)``，但 ``check()``
    會做 ``for _type in types:`` —— 傳入一個 type（而非 tuple）就一定爆
    ``TypeError: 'type' object is not iterable``。

    呢個修好只係換返正確嘅 ``(Color,)``，行為同原意一樣。
    如果將來 Pyto 官方修咗呢個 bug，呢個 patch 會自動讓路。

    ⚠️ 呢個函式喺 **module level** 執行。任何未捕捉嘅例外都會令成個
    widget import 失敗 → ``show_widget()`` 永遠唔會被叫 → iOS 顯示
    綠色 default template。所以呢度每一層都要自己企穩。
    """
    # 安全色：萬一連 dynamic 都搞唔掂，呢兩個係最後底線。
    try:
        _white = wd.Color.rgb(1.0, 1.0, 1.0)
        _black = wd.Color.rgb(0.0, 0.0, 0.0)
    except BaseException:
        return

    try:
        wd.Color.dynamic(light=_white, dark=_black)
        return  # 冇 bug，唔使 patch
    except BaseException:
        # 原本淨係捉 TypeError。但 `Color.dynamic` 缺失、權限問題、
        # 或者任何其他內部錯誤都會穿出去炸成個 module。
        # 呢度擴闊到 BaseException：patch 失敗唔應該令 widget 死。
        pass

    try:
        from widgets import Color, __PyColor__

        def _dynamic(light, dark):
            return Color(__PyColor__.colorWithLight(light.__py_color__, dark=dark.__py_color__))

        Color.dynamic = staticmethod(_dynamic)
    except BaseException:
        # `__PyColor__` 唔存在就由得佢。之後 BACKGROUND / PRIMARY 嘅
        # `Color.dynamic(...)` 會再 throw，但嗰陣已經喺 _dyn() 保護之下。
        pass


def _dyn(light, dark):
    """``Color.dynamic`` 嘅安全版：搞唔掂就退返深色色。

    真機實測背景：呢個 wrapper 係「綠色 default」嘅頭號防線。
    """
    return _safe(lambda: wd.Color.dynamic(light=light, dark=dark), dark)


_patch_color_dynamic()

# 時間由系統自動跳動（DynamicDate），其餘系統資訊每次 reload 重新讀取。
#
# 30 分鐘唔係隨意揀：WidgetKit 用「每日預算」分配 reload，Apple 官方講明
# 一般用家每日 40–70 次（大約 15–60 分鐘一次）。15 分鐘等於要求 96 次/日，
# 超咗上限，結果唔係更新得快，而係被系統 throttle／coalesce，得嚟變慢。
# iOS 27 更加收緊咗記憶體同電力預算，overshoot 嘅 widget 會被更快 throttle。
#
# 30 分鐘 = 48 次/日，穩穩喺預算內。以電量／儲存空間呢類資料來講，
# 半個鐘更新一次已經夠 — 真正要實時嘅係時間，而時間交畀 DynamicDate，
# 唔使靠 reload。
RELOAD_INTERVAL = timedelta(minutes=30)

WEEKDAYS = ("星期一", "星期二", "星期三", "星期四", "星期五", "星期六", "星期日")


def _safe(fn, fallback=None):
    """行 ``fn()``；任何例外都唔會向上傳，回傳 ``fallback``。

    成個 widget 都係「寧願少一樣，都唔好畫唔到」嘅設計：
    每個資料源、每個 widget family 都獨立包住。
    """
    try:
        return fn()
    except BaseException:
        return fallback


def _system_color(name, fallback):
    """用 iOS 系統語意色（自動跟淺／深色、tinted、clear 模式），舊版 Pyto 冇就用後備。

    **絕對唔好用 ``wd.COLOR_XXX`` 裸讀。**
    ``widgets`` 同 ``pyto_ui`` 係兩個獨立 module，常數集唔一樣；
    任何一個裸讀 `AttributeError` 都會喺 **import 階段**死掉，
    然後 iOS 就顯示綠色 default template（`show_widget()` 永遠冇被叫）。
    """
    return getattr(wd, f"COLOR_{name}", fallback)


def _rgb(r, g, b):
    """後備色：用 `Color.rgb` 砌，唔賴任何 `COLOR_*` 常數。"""
    return wd.Color.rgb(r, g, b)


# 配色跟 iOS 27 系統 widget：標準白／深灰底，文字同強調色用系統語意色，
# 咁喺 Liquid Glass 嘅 tinted／clear 模式下，系統先可以正確重新上色。
BACKGROUND = _dyn(
    wd.Color.rgb(1.0, 1.0, 1.0),
    wd.Color.rgb(0.11, 0.11, 0.118),
)
# 主文字色刻意唔用 COLOR_LABEL：extension 入面系統語意色係按 Pyto 主 app 嘅
# 外觀解析，同 widget 自己嘅淺／深色可能唔同步，會出現白底白字。
# 自訂 dynamic 色同背景一齊解析，一定對得上。
PRIMARY = _dyn(
    wd.Color.rgb(0.0, 0.0, 0.0),
    wd.Color.rgb(1.0, 1.0, 1.0),
)
SECONDARY = _system_color("SECONDARY_LABEL", PRIMARY)
TERTIARY = _system_color("TERTIARY_LABEL", SECONDARY)
ACCENT = _system_color("SYSTEM_RED", _rgb(1.0, 0.23, 0.19))  # 同系統「日曆」widget 一樣，用紅色標示星期
GREEN = _system_color("SYSTEM_GREEN", _rgb(0.20, 0.78, 0.35))
ORANGE = _system_color("SYSTEM_ORANGE", _rgb(1.0, 0.58, 0.0))
RED = _system_color("SYSTEM_RED", _rgb(1.0, 0.23, 0.19))
BLUE = _system_color("SYSTEM_BLUE", SECONDARY)
INDIGO = _system_color("SYSTEM_INDIGO", SECONDARY)
GRAY = _system_color("SYSTEM_GRAY", SECONDARY)
MISSING = "—"

# 儲存空間剩低過呢個比例就轉紅，同 iOS「iPhone 儲存空間」警告差唔多。
LOW_STORAGE_RATIO = 0.1


# --------------------------------------------------------------------------
# 系統資訊
# --------------------------------------------------------------------------


def _objc_class(name):
    from rubicon.objc import ObjCClass

    return ObjCClass(name)


def _py(value):
    """NSNumber／NSString → Python 值。

    rubicon 唔會自動轉換 ``objectForKey_`` 回傳嘅 NSNumber；直接 ``bool()``
    一個 ObjC 物件永遠係 True（例如 ``@NO`` 都當咗「充電中」）。
    """
    if value is None:
        return None
    try:
        from rubicon.objc import py_from_ns

        return py_from_ns(value)
    except Exception:
        return value


def read_battery():
    """回傳 (電量 0-1 或 None, 是否接住電源)。"""
    level, charging = _battery_via_uidevice()
    if level is None:
        level, charging = _battery_via_iokit()
    return level, charging


def _battery_via_uidevice():
    try:
        device = _objc_class("UIDevice").currentDevice
        device.batteryMonitoringEnabled = True
        level = float(device.batteryLevel)
        state = int(device.batteryState)
        if 0 <= level <= 1:
            return level, state in (2, 3)  # 2 = 充電中，3 = 已充滿（仍接住電）
    except Exception:
        pass
    return None, False


def _battery_via_iokit():
    """UIDevice 喺 widget 擴展入面經常回傳 -1，所以退一步用 IOKit 讀電源資訊。"""
    try:
        from ctypes import c_void_p

        from rubicon.objc import ObjCInstance
        from rubicon.objc.runtime import load_library

        iokit = load_library("IOKit")
        iokit.IOPSCopyPowerSourcesInfo.restype = c_void_p
        iokit.IOPSCopyPowerSourcesList.argtypes = [c_void_p]
        iokit.IOPSCopyPowerSourcesList.restype = c_void_p
        iokit.IOPSGetPowerSourceDescription.argtypes = [c_void_p, c_void_p]
        iokit.IOPSGetPowerSourceDescription.restype = c_void_p

        snapshot = iokit.IOPSCopyPowerSourcesInfo()
        if not snapshot:
            return None, False

        sources = ObjCInstance(iokit.IOPSCopyPowerSourcesList(snapshot))
        for source in sources:
            description = ObjCInstance(
                iokit.IOPSGetPowerSourceDescription(snapshot, source.ptr)
            )
            if description is None:
                continue

            current = _py(description.objectForKey_("Current Capacity"))
            maximum = _py(description.objectForKey_("Max Capacity"))
            if current is None or not maximum:
                continue

            level = min(max(float(current) / float(maximum), 0.0), 1.0)
            charging = _py(description.objectForKey_("Is Charging")) is True
            return level, charging
    except Exception:
        pass
    return None, False


def read_storage():
    """回傳 (可用位元組, 總位元組)。讀唔到就 (None, None)。"""
    free, total = _storage_via_foundation()
    if total:
        return free, total
    return _storage_via_statvfs()


def _storage_via_foundation():
    """同「設定 → 一般 → iPhone 儲存空間」一樣嘅數字（包括可清除空間）。"""
    try:
        home = _objc_class("NSURL").fileURLWithPath_(os.path.expanduser("~"))
        values = home.resourceValuesForKeys_error_(
            [
                "NSURLVolumeAvailableCapacityForImportantUsageKey",
                "NSURLVolumeTotalCapacityKey",
            ],
            None,
        )
        free = _py(values.objectForKey_("NSURLVolumeAvailableCapacityForImportantUsageKey"))
        total = _py(values.objectForKey_("NSURLVolumeTotalCapacityKey"))
        if total:
            return int(free), int(total)
    except Exception:
        pass
    return None, None


def _storage_via_statvfs():
    # iOS 嘅 "/" 係唯讀系統卷（sealed system volume），可用空間永遠係嗰個卷，
    # 唔係用家資料。所以先讀 home（資料卷），讀唔到先退返 "/"。
    for path in (os.path.expanduser("~"), "/"):
        try:
            stats = os.statvfs(path)
            total = stats.f_blocks * stats.f_frsize
            if total:
                return stats.f_bavail * stats.f_frsize, total
        except Exception:
            continue
    return None, None


def read_system():
    """回傳開機時間、iOS 版本、低耗電模式；讀唔到嘅項目會缺席。"""
    info = {}
    try:
        process = _objc_class("NSProcessInfo").processInfo
        info["version"] = _short_version(str(process.operatingSystemVersionString))
        info["low_power"] = bool(process.isLowPowerModeEnabled)
        # systemUptime 唔計睡眠時間，所以只係後備。
        info["uptime"] = float(process.systemUptime)
    except Exception:
        pass

    boot_uptime = _uptime_since_boot()
    if boot_uptime is not None:
        info["uptime"] = boot_uptime
    return info


def _uptime_since_boot():
    """由 ``kern.boottime`` 計真正開機至今嘅時間（包括睡眠）。"""
    try:
        import ctypes

        class _Timeval(ctypes.Structure):
            _fields_ = [("tv_sec", ctypes.c_long), ("tv_usec", ctypes.c_long)]

        libc = ctypes.CDLL(None)
        boot = _Timeval()
        size = ctypes.c_size_t(ctypes.sizeof(boot))
        if libc.sysctlbyname(b"kern.boottime", ctypes.byref(boot), ctypes.byref(size), None, 0):
            return None
        uptime = time.time() - boot.tv_sec
        return uptime if uptime > 0 else None
    except Exception:
        return None


def _short_version(raw):
    """"Version 18.1 (Build 22B83)" → "iOS 18.1"。"""
    match = re.search(r"Version\s+([\d.]+)", raw)
    return f"iOS {match.group(1)}" if match else raw


def format_bytes(value):
    """用十進制單位（1 GB = 1000³），同 iOS 設定入面顯示嘅一致。"""
    if value is None:
        return MISSING
    size = float(value)
    for unit in ("B", "KB", "MB"):
        if size < 1000:
            return f"{size:.0f} {unit}"
        size /= 1000
    return f"{size:.1f} GB" if size < 1000 else f"{size / 1000:.2f} TB"


def format_uptime(seconds):
    if seconds is None:
        return MISSING
    days, rest = divmod(int(seconds), 86400)
    hours, rest = divmod(rest, 3600)
    minutes = rest // 60
    if days:
        return f"{days} 天 {hours} 小時"
    if hours:
        return f"{hours} 小時 {minutes} 分"
    return f"{minutes} 分"


def format_battery(level):
    return MISSING if level is None else f"{round(level * 100)}%"


# --------------------------------------------------------------------------
# UI 元件
# --------------------------------------------------------------------------


def label(text, size=13, color=SECONDARY, bold=False):
    font = (
        wd.Font.bold_system_font_of_size(size)
        if bold
        else wd.Font.system_font_of_size(size)
    )
    return wd.Text(text, font=font, color=color)


def icon(name, color=SECONDARY, size=13):
    padding = wd.Padding(top=3, bottom=3, right=6)
    return wd.SystemSymbol(name, color=color, font_size=size, padding=padding)


def status_row(title, value, symbol, tint, value_color=PRIMARY):
    """仿「設定」App：彩色圖示 + 灰色標題 …… 粗體數值。"""
    return [
        icon(symbol, color=tint, size=14),
        label(title, size=14, color=SECONDARY),
        wd.Spacer(),
        label(value, size=14, color=value_color, bold=True),
    ]


def clock(now, size):
    # style=DATE_STYLE_TIME 交畀系統自動更新，唔需要靠 reload 跳秒。
    return wd.DynamicDate(
        now,
        style=wd.DATE_STYLE_TIME,
        font=wd.Font.bold_system_font_of_size(size),
        color=PRIMARY,
    )


def weekday_label(now, size=13):
    return label(WEEKDAYS[now.weekday()], size=size, color=ACCENT, bold=True)


def date_label(now, size=13):
    return label(f"{now.month}月{now.day}日", size=size, color=SECONDARY)


def header_row(now, trailing=()):
    """星期（紅）＋日期（灰），右邊可以擺狀態。"""
    return [weekday_label(now), date_label(now), wd.Spacer(), *trailing]


def battery_color(level, charging):
    if charging:
        return GREEN
    if level is None:
        return SECONDARY
    if level <= 0.2:
        return RED
    return ORANGE if level <= 0.4 else GREEN


def battery_symbol(level, charging):
    """跟住電量揀 SF Symbol，同狀態列嘅電池圖示一致。"""
    if charging:
        return "battery.100percent.bolt"
    if level is None:
        return "battery.0percent"
    for threshold, name in ((0.88, "100"), (0.63, "75"), (0.38, "50"), (0.13, "25")):
        if level >= threshold:
            return f"battery.{name}percent"
    return "battery.0percent"


def battery_chip(level, charging, size=13):
    color = battery_color(level, charging)
    return [
        icon(battery_symbol(level, charging), color=color, size=size),
        label(format_battery(level), size=size, color=color, bold=True),
    ]


def storage_color(free, total):
    if free is not None and total and free / total < LOW_STORAGE_RATIO:
        return RED
    return PRIMARY


# --------------------------------------------------------------------------
# 版面
# --------------------------------------------------------------------------


def build_small(layout, now, level, charging):
    layout.add_row([weekday_label(now, size=14), wd.Spacer()])
    layout.add_row([date_label(now), wd.Spacer()])
    layout.add_vertical_spacer()
    layout.add_row([clock(now, 42)])
    layout.add_vertical_spacer()
    layout.add_row([*battery_chip(level, charging), wd.Spacer()])
    layout.set_background_color(BACKGROUND)


def build_medium(layout, now, level, charging, free, total, system):
    layout.add_row(header_row(now, battery_chip(level, charging)))
    layout.add_vertical_spacer()
    layout.add_row([clock(now, 58)])
    layout.add_vertical_spacer()

    footer = [
        icon("internaldrive.fill", color=BLUE),
        label(f"{format_bytes(free)} 可用", color=storage_color(free, total)),
        wd.Spacer(),
    ]
    if system.get("low_power"):
        footer += [icon("leaf.fill", color=ORANGE), label("低耗電", color=ORANGE)]
    layout.add_row(footer)
    layout.set_background_color(BACKGROUND)


def build_large(layout, now, level, charging, free, total, system):
    battery_text = format_battery(level)
    if charging and level is not None:
        battery_text += " · 已充滿" if level >= 0.995 else " · 充電中"

    storage_text = format_bytes(free)
    if total:
        storage_text += f" / {format_bytes(total)}"

    layout.add_row(header_row(now))
    layout.add_vertical_spacer()
    layout.add_row([clock(now, 64)])
    layout.add_vertical_spacer()
    layout.add_vertical_divider()

    layout.add_row(
        status_row(
            "電量",
            battery_text,
            battery_symbol(level, charging),
            battery_color(level, charging),
            battery_color(level, charging),
        )
    )
    layout.add_row(
        status_row(
            "儲存空間", storage_text, "internaldrive.fill", BLUE, storage_color(free, total)
        )
    )
    layout.add_row(
        status_row("開機時間", format_uptime(system.get("uptime")), "clock.fill", INDIGO)
    )
    layout.add_row(
        status_row("系統版本", system.get("version", MISSING), "iphone.gen3", GRAY)
    )
    if system.get("low_power"):
        layout.add_row(status_row("低耗電模式", "已開啟", "leaf.fill", ORANGE, ORANGE))

    layout.set_background_color(BACKGROUND)


def _crumb(step):
    """足跡：同 launcher 共用 userkeys 嘅 trace，記低 widget 本體去到邊。

    硬崩潰（ObjC abort、被系統殺）try/except 捉唔到，只有逐步寫入先睇到死喺邊。
    直接行 i_widget.py（唔經 launcher）時 launcher 嘅 _crumb 唔存在，就靜靜略過。
    """
    try:
        import userkeys

        old = userkeys.get("i_widget.trace")
        userkeys.set(f"{old}\n   widget: {step}", "i_widget.trace")
    except BaseException:
        pass


def main():
    now = datetime.now()
    _crumb("main 開始")

    # 每個資料源都獨立保護。
    # 背景：真機 home screen 長期顯示綠色 default template，即係
    # wd.show_widget() 從來冇被叫過 —— main() 中途死咗。
    # 呢啲讀取全部依賴 iOS 專有 API（_objc_class / os.statvfs），
    # 任何一個喺某個 Pyto 版本或某次 reload 失敗就會令整個 widget 死。
    # 寧願少一項資料，都唔好成個唔見。
    _crumb("讀電量前")
    level, charging = _safe(lambda: read_battery(), (None, False))
    _crumb(f"讀電量後 {level}")
    free, total = _safe(lambda: read_storage(), (None, None))
    _crumb(f"讀儲存後 {free}/{total}")
    system = _safe(read_system, {})
    _crumb(f"讀系統後 {sorted(system)}")

    widget = _safe(wd.Widget)
    if widget is None:
        return

    # 每個 family 獨立保護：small 壞唔影響 large。
    for name, builder in (
        ("small_layout", lambda L: build_small(L, now, level, charging)),
        ("medium_layout", lambda L: build_medium(L, now, level, charging, free, total, system)),
        ("large_layout", lambda L: build_large(L, now, level, charging, free, total, system)),
        ("extra_large_layout", lambda L: build_large(L, now, level, charging, free, total, system)),
    ):
        layout = _safe(lambda n=name: getattr(widget, n))
        if layout is None:
            continue
        try:
            builder(layout)
        except BaseException as error:
            # 呢個 family 壞咗就補最基本內容，好過由 iOS 顯示綠色 template。
            _minimal_layout(layout, f"{name} 出錯", error, now)

    _safe(lambda: wd.schedule_next_reload(RELOAD_INTERVAL))
    _crumb("即將 show_widget")
    wd.show_widget(widget)
    _crumb("show_widget 已叫")


def _minimal_layout(layout, title, error, now):
    """最後防線：出錯嘅 family 都至少要有時間，唔可以空。"""
    for call, args in (
        (layout.add_row, [_safe(lambda: clock(now, 42))]),
        (layout.add_row, [_safe(lambda: date_label(now))]),
    ):
        _safe(lambda c=call, a=args: c([x for x in a if x is not None]))

    _safe(layout.add_vertical_spacer)
    for line in (title, f"{type(error).__name__}: {error}"[:110]):
        _safe(lambda s=line: layout.add_row([_safe(lambda t=s: wd.Text(t))]))
    _safe(lambda: layout.set_background_color(BACKGROUND))


# 連 main() 本身都爆（例如 datetime 唔存在），都要出到畫面。
try:
    main()
except BaseException as _fatal:
    try:
        from datetime import datetime as _dt

        _w = wd.Widget()
        _minimal_layout(_w.small_layout, "main() 失敗", _fatal, _dt.now())
        _safe(lambda: wd.schedule_next_reload(RELOAD_INTERVAL))
        wd.show_widget(_w)
    except BaseException:
        pass
