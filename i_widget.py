"""i-widget — iPhone Home Screen 嘅「時間／系統狀態」widget（Pyto 版本）。

用 Pyto 內置嘅 widgets API 寫成，唔需要 Mac 或 Xcode。
安裝步驟見 README.md。
"""

import os
import re
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
RELOAD_INTERVAL = timedelta(minutes=15)

WEEKDAYS = ("星期一", "星期二", "星期三", "星期四", "星期五", "星期六", "星期日")

BACKGROUND = wd.Color.dynamic(
    light=wd.Color.rgb(0.97, 0.97, 1.00),
    dark=wd.Color.rgb(0.07, 0.08, 0.11),
)
PRIMARY = wd.Color.dynamic(
    light=wd.Color.rgb(0.07, 0.08, 0.11),
    dark=wd.Color.rgb(0.96, 0.96, 1.00),
)
SECONDARY = wd.COLOR_SECONDARY_LABEL
GREEN = wd.COLOR_SYSTEM_GREEN
ORANGE = wd.COLOR_SYSTEM_ORANGE
RED = wd.COLOR_SYSTEM_RED
MISSING = "—"


# --------------------------------------------------------------------------
# 系統資訊
# --------------------------------------------------------------------------


def _objc_class(name):
    from rubicon.objc import ObjCClass

    return ObjCClass(name)


def read_battery():
    """回傳 (電量 0-1 或 None, 是否充電中)。"""
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
            return level, state in (2, 3)
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

            current = description.objectForKey_("Current Capacity")
            maximum = description.objectForKey_("Max Capacity")
            if current is None or not maximum:
                continue

            level = float(current) / float(maximum)
            charging = bool(description.objectForKey_("Is Charging"))
            return level, charging
    except Exception:
        pass
    return None, False


def read_storage():
    """回傳 (可用位元組, 總位元組)。"""
    try:
        stats = os.statvfs("/")
        return stats.f_bavail * stats.f_frsize, stats.f_blocks * stats.f_frsize
    except Exception:
        return None, None


def read_system():
    """回傳開機時間、iOS 版本、低耗電模式；讀唔到嘅項目會缺席。"""
    info = {}
    try:
        process = _objc_class("NSProcessInfo").processInfo
        info["uptime"] = float(process.systemUptime)
        info["version"] = _short_version(str(process.operatingSystemVersionString))
        info["low_power"] = bool(process.isLowPowerModeEnabled)
    except Exception:
        pass
    return info


def _short_version(raw):
    """"Version 18.1 (Build 22B83)" → "iOS 18.1"。"""
    match = re.search(r"Version\s+([\d.]+)", raw)
    return f"iOS {match.group(1)}" if match else raw


def format_bytes(value):
    if value is None:
        return MISSING
    size = float(value)
    for unit in ("B", "KB", "MB"):
        if size < 1024:
            return f"{size:.0f} {unit}"
        size /= 1024
    return f"{size:.1f} GB" if size < 1024 else f"{size / 1024:.1f} TB"


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


def status_icon(name, color=SECONDARY):
    padding = wd.Padding(top=3, bottom=3, right=5)
    return wd.SystemSymbol(name, color=color, font_size=13, padding=padding)


def status_text(text, color=PRIMARY, bold=False):
    return label(text, size=14, color=color, bold=bold)


def status_row(title, value, symbol, value_color=PRIMARY):
    return [
        status_icon(symbol),
        status_text(title, color=SECONDARY),
        wd.Spacer(),
        status_text(value, color=value_color, bold=True),
    ]


def clock(size):
    # style=DATE_STYLE_TIME 交畀系統自動更新，唔需要靠 reload 跳秒。
    return wd.DynamicDate(
        datetime.now(),
        style=wd.DATE_STYLE_TIME,
        font=wd.Font.bold_system_font_of_size(size),
        color=PRIMARY,
    )


def date_label(now):
    return label(f"{now.month}月{now.day}日 {WEEKDAYS[now.weekday()]}")


def battery_color(level, charging):
    if charging:
        return GREEN
    if level is None:
        return SECONDARY
    if level <= 0.2:
        return RED
    return ORANGE if level <= 0.4 else PRIMARY


# --------------------------------------------------------------------------
# 版面
# --------------------------------------------------------------------------


def build_small(layout, now):
    layout.add_vertical_spacer()
    layout.add_row([clock(44)])
    layout.add_row([date_label(now)])
    layout.add_vertical_spacer()
    layout.set_background_color(BACKGROUND)


def build_medium(layout, now, level, charging, free):
    battery_text = MISSING if level is None else f"{round(level * 100)}%"
    symbol = "battery.100.bolt" if charging else "minus.plus.batteryblock"

    layout.add_row([date_label(now)])
    layout.add_vertical_spacer()
    layout.add_row([clock(58)])
    layout.add_vertical_spacer()
    layout.add_row(
        [
            status_icon(symbol, color=battery_color(level, charging)),
            status_text(battery_text, color=battery_color(level, charging), bold=True),
            wd.Spacer(),
            status_text(format_bytes(free), color=SECONDARY),
        ]
    )
    layout.set_background_color(BACKGROUND)


def build_large(layout, now, level, charging, free, total, system):
    battery_text = MISSING if level is None else f"{round(level * 100)}%"
    if charging:
        battery_text += "（充電中）"
    symbol = "battery.100.bolt" if charging else "minus.plus.batteryblock"

    layout.add_row([date_label(now)])
    layout.add_vertical_spacer()
    layout.add_row([clock(64)])
    layout.add_vertical_spacer()
    layout.add_vertical_divider()

    storage_text = format_bytes(free)
    if total:
        storage_text += f" / {format_bytes(total)}"

    layout.add_row(
        status_row("電量", battery_text, symbol, battery_color(level, charging))
    )
    layout.add_row(status_row("儲存空間", storage_text, "internaldrive"))
    layout.add_row(
        status_row("開機時間", format_uptime(system.get("uptime")), "clock")
    )
    layout.add_row(
        status_row("系統版本", system.get("version", MISSING), "gear")
    )
    if system.get("low_power"):
        layout.add_row(status_row("低耗電模式", "已開啟", "bolt", ORANGE))

    layout.set_background_color(BACKGROUND)


def main():
    now = datetime.now()
    level, charging = read_battery()
    free, total = read_storage()
    system = read_system()

    widget = wd.Widget()
    build_small(widget.small_layout, now)
    build_medium(widget.medium_layout, now, level, charging, free)
    build_large(widget.large_layout, now, level, charging, free, total, system)
    build_large(widget.extra_large_layout, now, level, charging, free, total, system)

    wd.schedule_next_reload(RELOAD_INTERVAL)
    wd.show_widget(widget)


main()