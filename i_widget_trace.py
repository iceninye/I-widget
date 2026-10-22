"""讀取 launcher 留低嘅足跡（真機除錯用）。

用法：喺 Pyto 入面直接行呢隻 script，console 會印出足跡；
同時亦會砌一個 widget（可以放落 home screen 睇）。

足跡由 i_widget_launcher.py（i_widget.trace）同 i_widget.py（i_widget.trace2）
每過一個關卡寫入 userkeys。i_widget.banned = 曾經令 process 死過、而家被跳過嘅元件。
最後一行 = 最後去到嘅位置；``====`` 分隔每一輪 reload。
"""
import widgets as wd

try:
    import userkeys

    parts = []
    for key in ("i_widget.trace", "i_widget.trace2", "i_widget.banned", "i_widget.inflight"):
        try:
            parts.append(f"--- {key}\n{userkeys.get(key)}")
        except BaseException:
            parts.append(f"--- {key}\n(冇)")
    trace = "\n".join(parts)
except BaseException as error:
    trace = f"(讀唔到足跡：{type(error).__name__}: {error})"

print(trace)

lines = (trace or "(冇足跡)").splitlines()[-14:]
widget = wd.Widget()
for name in ("small_layout", "medium_layout", "large_layout", "extra_large_layout"):
    layout = getattr(widget, name, None)
    if layout is None:
        continue
    for line in lines:
        layout.add_row([wd.Text(line[:48])])
wd.show_widget(widget)
