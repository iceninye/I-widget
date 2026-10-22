"""
i-widget ULTRA-SAFE — 保證出到畫面版本。

背景
----
之前幾個版本喺真機 home screen 只見到「綠色 default template」。
綠色 = wd.show_widget() 從來冇被叫過 = script 喺中途死咗。

呢個版本設計原則：**任何一步失敗都唔會令畫面消失**。

做法
----
1. 所有可能不存在嘅 API（COLOR_*、Font.*、extra_large_layout）都用
   getattr 包住，缺咗就 fallback。
2. 唔用 launcher、唔上網、唔用 userkeys — 淨係一個檔自我完結。
3. 主體寫喺 try 入面，就算死都會掉入「錯誤畫面」路徑；
   錯誤畫面用最低風險嘅 API。
4. 第一行顯示版本，方便確認真係行緊呢個檔案。

用法
----
Pyto 加 widget → Script 貼晒呢個檔案 → 放落 home screen。
睇到時間就代表成功；如果出錯，畫面會直接印出錯乜。
"""

VERSION = "safe-1.0"

import widgets as wd


def _safe(fn, fallback=None):
    """行 fn()，任何例外都唔會向上傳。"""
    try:
        return fn()
    except BaseException:
        return fallback


def _color(r, g, b):
    return _safe(lambda: wd.Color.rgb(r, g, b))


def _dyn(light, dark):
    """自訂動態色。如果 Color.dynamic 有 Pyto 19.0 嗰個 TypeError bug，
    就退返固定色 —— 寧願顏色唔完美，都唔好死。"""
    def build():
        from widgets import Color, __PyColor__

        return Color(__PyColor__.colorWithLight(light.__py_color__, dark=dark.__py_color__))

    try:
        return wd.Color.dynamic(light=light, dark=dark)
    except BaseException:
        return _safe(build, dark)


WHITE = _color(1.0, 1.0, 1.0)
BLACK = _color(0.0, 0.0, 0.0)
DARK_BG = _color(0.11, 0.11, 0.118)

BACKGROUND = _dyn(_color(1.0, 1.0, 1.0), _color(0.11, 0.11, 0.118))
PRIMARY = _dyn(_color(0.0, 0.0, 0.0), _color(1.0, 1.0, 1.0))
# 系統語意色：存在就用，唔存在就用上面砌好嘅自訂色。
MUTED = _safe(lambda: getattr(wd, "COLOR_SECONDARY_LABEL"), PRIMARY)
ACCENT = _safe(lambda: getattr(wd, "COLOR_SYSTEM_RED"), _color(1.0, 0.23, 0.19))


def _font(size, bold=False):
    name = "bold_system_font_of_size" if bold else "system_font_of_size"
    return _safe(lambda: getattr(wd.Font, name)(size))


def _text(value, size=12, bold=False, color=None):
    kwargs = {}
    f = _font(size, bold)
    if f is not None:
        kwargs["font"] = f
    if color is not None:
        kwargs["color"] = color
    node = _safe(lambda: wd.Text(value, **kwargs))
    if node is None:
        node = _safe(lambda: wd.Text(value))
    return node


def _render(lines):
    """lines = [(文字, 字級, 粗體, 顏色)]"""
    widget = _safe(wd.Widget)
    if widget is None:
        return False
    _safe(lambda: setattr(widget, "background_color", BACKGROUND))

    # 每個 family 都包 try：一個壞唔影響其他。
    layouts = []
    for name in ("small_layout", "medium_layout", "large_layout", "extra_large_layout"):
        layout = _safe(lambda n=name: getattr(widget, n))
        if layout is not None:
            layouts.append(layout)

    for layout in layouts:
        _safe(layout.add_vertical_spacer)
        for value, size, bold, color in lines:
            node = _text(value, size, bold, color)
            if node is not None:
                _safe(lambda n=node, L=layout: L.add_row([n]))
        _safe(layout.add_vertical_spacer)

    _safe(wd.schedule_next_reload, None)
    wd.show_widget(widget)
    return True


def _main():
    from datetime import datetime

    now = datetime.now()
    weekdays = ("一", "二", "三", "四", "五", "六", "日")
    weekday = weekdays[now.weekday()]

    time_str = now.strftime("%H:%M")
    date_str = f"{now.month}月{now.day}日 星期{weekday}"

    # 秒數：證明 widget 真係每 30 分鐘 reload 而唔係卡住
    seconds = now.strftime(":%S")

    return _render([
        (f"i-widget {VERSION}", 10, False, MUTED),
        (time_str + seconds, 40, True, PRIMARY),
        (date_str, 13, False, MUTED),
        (ACCENT and f"星期{weekday}", 12, True, ACCENT),
    ])


try:
    from datetime import timedelta

    try:
        _main()
    except BaseException as error:
        _render([
            ("i-widget 執行錯誤", 14, True, ACCENT),
            (f"{type(error).__name__}", 11, False, PRIMARY),
            (str(error)[:120], 10, False, MUTED),
            (f"版本 {VERSION}", 9, False, MUTED),
        ])
except BaseException:
    # 連 datetime 都 import 唔到 → 極簡畫面
    try:
        w = wd.Widget()
        w.small_layout.add_row([wd.Text("i-widget")])
        wd.show_widget(w)
    except BaseException:
        pass