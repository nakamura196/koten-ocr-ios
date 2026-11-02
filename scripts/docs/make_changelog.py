"""CHANGELOG.md から、紹介サイトの更新履歴のページ（日英）を作る。

出力: docs/changelog.md・docs/changelog-en.md（https://kotenocr.ldas.jp/changelog.html ほか）
使い方: python3 scripts/docs/make_changelog.py（リポジトリの直下で）

CHANGELOG.md の各行は「日本語 / English」の形で書く。
最初の「 / 」のうち、後ろが英字の大文字で始まるところで日英を分ける。
「(Unreleased)」の版はサイトに載せない（App Store に出てから日付を入れて走らせ直す）。
"""

import datetime
import re
from pathlib import Path

SRC = Path("CHANGELOG.md")
MONTHS = "January February March April May June July August September October November December".split()

HEAD = {
    "ja": """---
title: 更新履歴
eyebrow: KotenOCR
lead: 版ごとに、何が変わったかをまとめています。新しい版が上です。
alternate: {{ title: English, url: changelog-en.html, lang: en }}
---

> App Store からの自動アップデートを切っている場合は、App Store の「アップデート」から新しい版に替えてください。
{{: .point }}

日付は日本時間です。最新は {latest} です。
""",
    "en": """---
lang: en
home_url: /en.html
image: /assets/ogp/ogp-en.png
title: Changelog
eyebrow: KotenOCR
lead: What changed in each version. Newest first.
alternate: {{ title: 日本語, url: changelog.html, lang: ja }}
nav:
  - {{ title: Home, url: en.html }}
  - {{ title: GitHub, url: "https://github.com/nakamura196/koten-ocr-ios" }}
footer: "Contact: nakamura.satoru@mail.u-tokyo.ac.jp"
---

> If automatic updates are off, update from the App Store's Updates list.
{{: .point }}

Dates are in Japan time. The latest version is {latest}.
""",
}


def split_line(text: str) -> tuple[str, str]:
    m = re.search(r" / (?=[A-Z])", text)
    if not m:
        return text, text
    return text[: m.start()].strip(), text[m.end():].strip()


def fmt_date(d: str, lang: str) -> str:
    y, mo, da = (int(x) for x in d.split("-"))
    datetime.date(y, mo, da)  # 日付として正しいか確かめる
    return f"{y}年{mo}月{da}日" if lang == "ja" else f"{da} {MONTHS[mo - 1]} {y}"


def main() -> None:
    versions: list[tuple[str, str, list[str]]] = []
    for line in SRC.read_text().splitlines():
        m = re.match(r"^## (\S+) \((.+)\)", line)
        if m:
            versions.append((m.group(1), m.group(2), []))
        elif line.startswith("- ") and versions:
            versions[-1][2].append(line[2:])
    versions = [v for v in versions if re.fullmatch(r"\d{4}-\d{2}-\d{2}", v[1])]

    for lang, out in (("ja", "docs/changelog.md"), ("en", "docs/changelog-en.md")):
        ver, date, _ = versions[0]
        latest = f"{ver}（{fmt_date(date, lang)}）" if lang == "ja" else f"{ver} ({fmt_date(date, lang)})"
        parts = [HEAD[lang].format(latest=latest)]
        for ver, date, items in versions:
            title = f"{ver}（{fmt_date(date, lang)}）" if lang == "ja" else f"{ver} ({fmt_date(date, lang)})"
            parts.append(f"\n### {title}\n")
            for it in items:
                ja, en = split_line(it)
                parts.append(f"- {ja if lang == 'ja' else en}")
        Path(out).write_text("\n".join(parts) + "\n")
        print(out, len(versions), "versions")


if __name__ == "__main__":
    main()
