"""i-widget — iPhone Home Screen 嘅「時間／系統狀態」widget（Pyto 版本）。

用 Pyto 內置嘅 widgets API 寫成，唔需要 Mac 或 Xcode。
安裝步驟見 README.md。
"""

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
    """
    try:
        wd.Color.dynamic(light=wd.Color.rgb(0.0, 0.0, 0.0), dark=wd.Color.rgb(1.0, 1.0, 1.0))
        return  # 冇 bug，唔使 patch
    except TypeError:
        pass

    from widgets import Color, __PyColor__

    def _dynamic(light, dark):
        return Color(__PyColor__.colorWithLight(light.__py_color__, dark=dark.__py_color__))

    Color.dynamic = staticmethod(_dynamic)


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


def _system_color(name, fallback):
    """用 iOS 系統語意色（自動跟淺／深色、tinted、clear 模式），舊版 Pyto 冇就用後備。"""
    return getattr(wd, f"COLOR_{name}", fallback)


# 配色跟 iOS 27 系統 widget：標準白／深灰底，文字同強調色用系統語意色，
# 咁喺 Liquid Glass 嘅 tinted／clear 模式下，系統先可以正確重新上色。
BACKGROUND = wd.Color.dynamic(
    light=wd.Color.rgb(1.0, 1.0, 1.0),
    dark=wd.Color.rgb(0.11, 0.11, 0.118),
)
# 主文字色刻意唔用 COLOR_LABEL：extension 入面系統語意色係按 Pyto 主 app 嘅
# 外觀解析，同 widget 自己嘅淺／深色可能唔同步，會出現白底白字。
# 自訂 dynamic 色同背景一齊解析，一定對得上。
PRIMARY = wd.Color.dynamic(
    light=wd.Color.rgb(0.0, 0.0, 0.0),
    dark=wd.Color.rgb(1.0, 1.0, 1.0),
)
SECONDARY = wd.COLOR_SECONDARY_LABEL
TERTIARY = _system_color("TERTIARY_LABEL", SECONDARY)
ACCENT = wd.COLOR_SYSTEM_RED  # 同系統「日曆」widget 一樣，用紅色標示星期
GREEN = wd.COLOR_SYSTEM_GREEN
ORANGE = wd.COLOR_SYSTEM_ORANGE
RED = wd.COLOR_SYSTEM_RED
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


def main():
    now = datetime.now()
    level, charging = read_battery()
    free, total = read_storage()
    system = read_system()

    widget = wd.Widget()
    build_small(widget.small_layout, now, level, charging)
    build_medium(widget.medium_layout, now, level, charging, free, total, system)
    build_large(widget.large_layout, now, level, charging, free, total, system)
    build_large(widget.extra_large_layout, now, level, charging, free, total, system)

    wd.schedule_next_reload(RELOAD_INTERVAL)
    wd.show_widget(widget)


main()
