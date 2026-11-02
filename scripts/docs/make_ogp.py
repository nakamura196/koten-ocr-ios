"""共有用の画像（OGP、1200×630）を日英 1 枚ずつ作る。

出力: docs/assets/ogp/ogp-ja.png・ogp-en.png（_config.yml と英語ページの image が指している）
元にする画面写真: screenshots/marketing/{ja,en}/marketing_02_iphone.png（App Store 用の画像）。写真を撮り直したら、これも走らせ直す。
使い方: python3 scripts/docs/make_ogp.py（リポジトリの直下で。Pillow とヒラギノ角ゴシックが要る）
"""

from PIL import Image, ImageDraw, ImageFilter, ImageFont

APP = "KotenOCR"
W, H = 1200, 630
FONT = "/System/Library/Fonts/ヒラギノ角ゴシック W{}.ttc"
ACCENT = "#b5452f"  # 朱（アプリの KotenColor.shu）

# 3 行の説明と、その下の小さな 1 行
TEXT = {
    "ja": ("くずし字も活字も、", "iPhone で撮るだけで", "文字にするアプリ", "読み取りは端末の中だけ。無料"),
    "en": ("Photograph a page,", "get the text: kuzushiji", "and modern Japanese", "Runs entirely on your iPhone. Free"),
}

# 画面写真の幅と位置。タイトル（52px で右端が約 622px）に重ならないよう右に寄せる
SHOT_W = 360
SHOT_X, SHOT_Y = W - SHOT_W - 60, 40


def font(weight: int, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(FONT.format(weight), size)


def paste_screenshot(im: Image.Image, lang: str) -> None:
    shot = Image.open(f"screenshots/marketing/{lang}/marketing_02_iphone.png").convert("RGB")
    sh = int(shot.height * SHOT_W / shot.width)
    shot = shot.resize((SHOT_W, sh), Image.LANCZOS)
    # 下端は画像の外へ流す（窓の下半分は見せなくてよい）
    h = min(sh, H - SHOT_Y + 40)

    shadow = Image.new("RGBA", (SHOT_W + 40, h + 40), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [20, 20, SHOT_W + 20, h + 20], 14, fill=(15, 23, 42, 60)
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(12))
    im.paste(shadow, (SHOT_X - 20, SHOT_Y - 14), shadow)

    mask = Image.new("L", (SHOT_W, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, SHOT_W, h + 30], 14, fill=255)
    im.paste(shot.crop((0, 0, SHOT_W, h)), (SHOT_X, SHOT_Y), mask)


def main() -> None:
    for lang, lines in TEXT.items():
        im = Image.new("RGB", (W, H), "#f3ebdc")
        d = ImageDraw.Draw(im)
        d.rectangle([0, 0, W, 10], fill=ACCENT)
        paste_screenshot(im, lang)

        d.text((64, 88), "iPhone · iPad", font=font(6, 26), fill=ACCENT)
        d.text((64, 128), APP, font=font(8, 52), fill="#2b2622")
        body = font(6, 34 if lang == "ja" else 36)
        for i, t in enumerate(lines[:3]):
            d.text((64, 250 + i * 56), t, font=body, fill="#2b2622")
        d.text((64, 450), lines[3], font=font(3, 26), fill="#6b5f52")

        out = f"docs/assets/ogp/ogp-{lang}.png"
        im.save(out, optimize=True)
        print(out, im.size)


if __name__ == "__main__":
    main()
