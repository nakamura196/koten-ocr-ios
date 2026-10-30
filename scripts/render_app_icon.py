#!/usr/bin/env python3
"""Render the KotenOCR app icon (design (ii): scan-frame corners + 典, washi / ink / 朱).

Writes 1024x1024 PNGs without alpha into KotenOCR/Assets.xcassets/AppIcon.appiconset
(light, dark, and a greyscale tinted variant) and a 512px copy for AppIconDisplay.

Requires Google Chrome (headless) and Pillow. Fonts are loaded from Google Fonts:
Noto Serif JP Black (典) and Yuji Syuku (background kana). Both are SIL Open Font License 1.1.

Usage: python3 scripts/render_app_icon.py
"""
import json
import pathlib
import subprocess
import tempfile

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
ASSETS = ROOT / "KotenOCR" / "Assets.xcassets"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
GOOGLE = ('<link href="https://fonts.googleapis.com/css2?family=Noto+Serif+JP:wght@900'
          '&family=Yuji+Syuku&display=block" rel="stylesheet">')


def paper_defs(pid):
    return f'''<defs>
<filter id="tex{pid}" x="0" y="0" width="100%" height="100%"><feTurbulence type="fractalNoise" baseFrequency="0.9" numOctaves="2" seed="4"/><feColorMatrix values="0 0 0 0 0.45  0 0 0 0 0.33  0 0 0 0 0.18  0 0 0 0.10 0"/><feComposite in2="SourceGraphic" operator="in"/></filter>
<filter id="rough{pid}"><feTurbulence type="fractalNoise" baseFrequency="0.045" numOctaves="3" seed="7"/><feDisplacementMap in="SourceGraphic" scale="14"/></filter>
<radialGradient id="pg{pid}" cx="35%" cy="25%" r="90%"><stop offset="0" stop-color="#faf4e8"/><stop offset="1" stop-color="#eadcc2"/></radialGradient>
</defs>'''


def logo(kind, mode="light", pid=None):
    pid = pid or f"{kind}{mode}"
    dark = mode == "dark"
    tint = mode == "tinted"
    if tint:
        bg = '<rect width="1024" height="1024" fill="#141414"/>'
        ink, shu, paper = "#e9d3b8", "#e9d3b8", "#141414"
    elif dark:
        bg = '<rect width="1024" height="1024" fill="#1d1a17"/>'
        ink, shu, paper = "#f1e6d2", "#e0684c", "#1d1a17"
    else:
        bg = f'<rect width="1024" height="1024" fill="url(#pg{pid})"/><rect width="1024" height="1024" fill="#fff" filter="url(#tex{pid})"/>'
        ink, shu, paper = "#231f1c", "#b5452f", "#f3ebdc"
    serif = "'Noto Serif JP', serif"
    if kind == "seal":
        body = f'''<g transform="rotate(-4 512 512)" filter="url(#rough{pid})">
<rect x="212" y="212" width="600" height="600" rx="56" fill="{shu}"/>
<rect x="250" y="250" width="524" height="524" rx="30" fill="none" stroke="{paper}" stroke-width="14"/>
<text x="512" y="540" text-anchor="middle" dominant-baseline="central" font-family="{serif}" font-weight="900" font-size="400" fill="{paper}">典</text></g>'''
    elif kind == "evo":
        kana = "" if tint else f'''<g font-family="'Yuji Syuku', serif" font-size="150" fill="{ink}" opacity="{.10 if not dark else .14}">
<text x="610" y="150">ゐ</text><text x="880" y="140">そ</text><text x="30" y="590">あ</text><text x="870" y="420">ふ</text><text x="40" y="960">ろ</text><text x="880" y="960">ゑ</text></g>'''
        c = shu
        sw = 34
        corners = f'''<g fill="none" stroke="{c}" stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round">
<path d="M190 330 V230 Q190 185 235 185 H335"/><path d="M689 185 H789 Q834 185 834 230 V330"/>
<path d="M190 694 V794 Q190 839 235 839 H335"/><path d="M689 839 H789 Q834 839 834 794 V694"/></g>'''
        body = f'''{kana}{corners}<text x="512" y="530" text-anchor="middle" dominant-baseline="central" font-family="{serif}" font-weight="900" font-size="430" fill="{ink}">典</text>'''
    else:  # brush
        body = f'''<text x="500" y="540" text-anchor="middle" dominant-baseline="central" font-family="'Yuji Syuku', serif" font-size="640" fill="{ink}">典</text>
<g fill="none" stroke="{shu}" stroke-width="30" stroke-linecap="round" stroke-linejoin="round"><path d="M760 850 H850 V760"/><path d="M174 264 V174 H264"/></g>'''
    return f'<svg viewBox="0 0 1024 1024" xmlns="http://www.w3.org/2000/svg">{paper_defs(pid)}{bg}{body}</svg>'




def render(mode, out_png):
    svg = logo("evo", mode, "i" + mode)
    html = (f'<!doctype html><html><head><meta charset="utf-8">{GOOGLE}<style>html,body{{margin:0;padding:0;'
            f'width:1024px;height:1024px;overflow:hidden}}svg{{display:block;width:1024px;height:1024px}}</style>'
            f'</head><body>{svg}</body></html>')
    with tempfile.TemporaryDirectory() as tmp:
        page = pathlib.Path(tmp) / f"{mode}.html"
        page.write_text(html, encoding="utf-8")
        subprocess.run([CHROME, "--headless=new", "--hide-scrollbars", "--force-device-scale-factor=1",
                        "--window-size=1024,1024", "--virtual-time-budget=15000",
                        f"--screenshot={out_png}", page.as_uri()], check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def main():
    icon_dir = ASSETS / "AppIcon.appiconset"
    with tempfile.TemporaryDirectory() as tmp:
        tmp = pathlib.Path(tmp)
        for mode in ("light", "dark", "tinted"):
            render(mode, tmp / f"{mode}.png")
        Image.open(tmp / "light.png").convert("RGB").save(icon_dir / "AppIcon.png", optimize=True)
        Image.open(tmp / "dark.png").convert("RGB").save(icon_dir / "AppIcon-dark.png", optimize=True)
        # Tinted icons should be greyscale; iOS applies the tint colour.
        Image.open(tmp / "tinted.png").convert("L").convert("RGB").save(icon_dir / "AppIcon-tinted.png", optimize=True)
        Image.open(tmp / "light.png").convert("RGB").resize((512, 512), Image.LANCZOS).save(
            ASSETS / "AppIconDisplay.imageset" / "AppIcon.png", optimize=True)
    print("icons written to", icon_dir)


if __name__ == "__main__":
    main()
