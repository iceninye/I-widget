"""重新產生 i_widget.fingerprint。

Launcher 用呢個檔案嘅內容判斷「遠端係咪有新版本」。只要 i_widget.py
改咗，就跑一次呢個 script（commit 前），或者直接靠 GitHub Action 自動做。

    python3 make_fingerprint.py

Fingerprint = i_widget.py 內容嘅 SHA256 前 16 個字元。
用內容 hash 而唔係 commit SHA，因為 device 只需要知道「變咗未」。
"""

import hashlib
import pathlib

HERE = pathlib.Path(__file__).resolve().parent
WIDGET = HERE / "i_widget.py"
OUTPUT = HERE / "i_widget.fingerprint"
LENGTH = 16


def fingerprint(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()[:LENGTH]


def main() -> None:
    value = fingerprint(WIDGET)
    previous = OUTPUT.read_text().strip() if OUTPUT.exists() else None

    OUTPUT.write_text(value + "\n", encoding="utf-8")

    if previous == value:
        print(f"fingerprint 無變：{value}")
    else:
        print(f"fingerprint: {previous or '(無)'} → {value}")


if __name__ == "__main__":
    main()