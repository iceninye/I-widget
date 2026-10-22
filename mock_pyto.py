"""測試用嘅 Pyto 假模組：``widgets`` 同 ``userkeys``。

照抄 Pyto 真實 API 簽名（包括 Pyto 19.0 ``Color.dynamic()`` 嘅 bug），
import 呢個模組就會將兩者註冊入 ``sys.modules``。
"""
import sys
import types


# ---------------------------------------------------------------- widgets
class __PyColor__:
    @staticmethod
    def colorWithRed(r, green=0, blue=0, alpha=1): return ("rgb", r, green, blue, alpha)
    @staticmethod
    def colorWithLight(light, dark=None): return ("dyn", light, dark)


def check(_object, name, types_):
    for _type in types_:
        if isinstance(_object, _type): return
    raise TypeError("Invalid value type")


class Color:
    def __init__(self, c): self.__py_color__ = c
    @classmethod
    def rgb(cls, red, green, blue, alpha=1.0):
        for v in (red, green, blue, alpha):
            assert isinstance(v, float) and 0 <= v <= 1, f"rgb 要 0-1 float，收到 {v!r}"
        return cls(__PyColor__.colorWithRed(red, green, blue, alpha))
    @classmethod
    def dynamic(cls, light, dark):   # Pyto 19.0 有 bug 的寫法
        check(light, "light", Color)
        return cls(__PyColor__.colorWithLight(light.__py_color__, dark=dark.__py_color__))
    def __repr__(self): return f"Color({self.__py_color__[0]})"


DATE_STYLE_DATE, DATE_STYLE_OFFSET, DATE_STYLE_RELATIVE, DATE_STYLE_TIME, DATE_STYLE_TIMER = 0, 1, 2, 3, 4


class Font:
    def __init__(self, name, size): self.name, self.size = name, size
    @classmethod
    def system_font_of_size(cls, size): return cls("sys", size)
    @classmethod
    def bold_system_font_of_size(cls, size): return cls("bold", size)


class Padding:
    def __init__(self, top=0, bottom=0, left=0, right=0):
        self.top, self.bottom, self.left, self.right = top, bottom, left, right


class Component:
    def __init__(self, *pos, **kw): self.__args, self.__kw = pos, kw
    def __repr__(self): return type(self).__name__


class Text(Component): pass
class DynamicDate(Component): pass
class SystemSymbol(Component): pass
class Spacer: pass


class WidgetLayout:
    def __init__(self): self.rows = []; self.row_styles = []; self.background = None
    def add_row(self, row, background_color=None, corner_radius=0, link=None):
        # 照抄 Pyto：row 係 list；可以有 background_color／corner_radius（卡片行）
        assert isinstance(row, list), "add_row 要 list"
        self.rows.append(row)
        self.row_styles.append((background_color, corner_radius))
    def add_vertical_spacer(self): self.rows.append("<v>"); self.row_styles.append(None)
    def add_vertical_divider(self, color=None): self.rows.append("|"); self.row_styles.append(None)
    def set_background_color(self, color): self.background = color


class Widget:
    def __init__(self):
        self.small_layout = WidgetLayout(); self.medium_layout = WidgetLayout()
        self.large_layout = WidgetLayout(); self.extra_large_layout = WidgetLayout()


SHOWN = []
RELOADS = []
def show_widget(w): SHOWN.append(w)
def schedule_next_reload(t): RELOADS.append(t)


wd = types.ModuleType("widgets")
for _k in ("Color", "Font", "Padding", "Text", "DynamicDate", "SystemSymbol", "Spacer",
           "Widget", "WidgetLayout", "DATE_STYLE_DATE", "DATE_STYLE_OFFSET",
           "DATE_STYLE_RELATIVE", "DATE_STYLE_TIME", "DATE_STYLE_TIMER",
           "show_widget", "schedule_next_reload", "__PyColor__"):
    setattr(wd, _k, globals()[_k])
for _n in ("LABEL", "SECONDARY_LABEL", "TERTIARY_LABEL", "SYSTEM_GREEN", "SYSTEM_ORANGE",
           "SYSTEM_RED", "SYSTEM_BLUE", "SYSTEM_INDIGO", "SYSTEM_GRAY",
           "TERTIARY_SYSTEM_FILL"):
    setattr(wd, f"COLOR_{_n}", Color(f"const:{_n}"))
sys.modules["widgets"] = wd


def text_of(component):
    """Text 的文字可能在位置參數或 kwargs，兩邊都試。"""
    args = getattr(component, "_Component__args", ())
    kw = getattr(component, "_Component__kw", {})
    return args[0] if args else kw.get("text")


# ---------------------------------------------------------------- userkeys
# 官方 userkeys = NSUserDefaults suite "group.pyto"，extension 同主 app 共用。
# 呢個 mock 用一個全域 dict 模擬「跨執行持久」。
UK_STORE = {}
UK_STATE = {"broken": False}


def _uk_get(key):
    if UK_STATE["broken"]:
        raise RuntimeError("NSUserDefaults unavailable")
    if key not in UK_STORE:
        raise KeyError(key)          # 官方 get() 對冇呢個 key 會 raise KeyError
    return UK_STORE[key]


def _uk_set(value, key):
    if UK_STATE["broken"]:
        raise RuntimeError("NSUserDefaults unavailable")
    UK_STORE[key] = value


def _uk_delete(key):
    if UK_STATE["broken"]:
        raise RuntimeError("NSUserDefaults unavailable")
    if key not in UK_STORE:
        raise KeyError(key)
    del UK_STORE[key]


uk = types.ModuleType("userkeys")
uk.get, uk.set, uk.delete = _uk_get, _uk_set, _uk_delete
sys.modules["userkeys"] = uk
