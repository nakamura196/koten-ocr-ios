"""Step 1: choose the evaluation pages from the CODH 日本古典籍くずし字データセット (v2) and build
line-level reference text from its character coordinates.

Input : data/raw/<book>.zip  (http://codh.rois.ac.jp/char-shape/dataset/v2/<book>.zip, CC BY-SA 4.0)
Output: data/pages/<book>_<page>.jpg   original page image (extracted unchanged)
        data/pages/<book>_<page>.json  reference lines (right-to-left) + selection stats
        pages_selected.csv             committed list of the chosen pages (no images, no transcripts)

Run:  python -I select_pages.py
"""
import csv
import json
import os
import random
import statistics
import sys
import unicodedata
import zipfile
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.join(HERE, "data", "raw")
OUT = os.path.join(HERE, "data", "pages")

SEED = 20261029
BOOKS = ["200015843", "200005798", "200008316"]
PER_BOOK = 10
BOOK_TITLE = {"200015843": "日本永代蔵", "200005798": "世間胸算用／大晦日ハ一日千金", "200008316": "武家義理物語"}

# Eligibility (the OCR model is never consulted when selecting pages)
MIN_CHARS = 150          # enough text to measure CER
MIN_LINES = 8
MAX_LINES = 20
MAX_GAP_RATIO = 1.0      # gap between consecutive characters in a line, in units of median char height
MIN_COLUMNS_OK = 0.95    # fraction of characters that fall in a "clean" line (see reconstruct_lines)


def rows_by_page(z, book):
    with z.open(f"{book}/{book}_coordinate.csv") as f:
        rd = csv.DictReader((l.decode("utf-8") for l in f))
        pages = defaultdict(list)
        for r in rd:
            pages[r["Image"]].append(r)
    return pages


def reconstruct_lines(rows):
    """CODH gives characters in reading order inside a 'Block' but no line boundaries.
    A new line starts when the next character is clearly to the left and not lower than the previous one."""
    blocks = defaultdict(list)
    for r in rows:
        blocks[r["Block ID"]].append(r)
    lines = []
    for bid in sorted(blocks):
        chars = sorted(blocks[bid], key=lambda r: int(r["Char ID"][1:]))
        med_w = statistics.median(int(c["Width"]) for c in chars)
        cur = []
        for c in chars:
            cx = int(c["X"]) + int(c["Width"]) / 2
            cy = int(c["Y"]) + int(c["Height"]) / 2
            if cur:
                px = int(cur[-1]["X"]) + int(cur[-1]["Width"]) / 2
                py = int(cur[-1]["Y"]) + int(cur[-1]["Height"]) / 2
                if px - cx > 0.6 * med_w and cy < py:
                    lines.append((bid, cur))
                    cur = []
            cur.append(c)
        if cur:
            lines.append((bid, cur))
    return lines


def line_text(chars):
    # CODH stores each character as "U+XXXX"
    return "".join(chr(int(c["Unicode"][2:], 16)) for c in chars)


def page_stats(rows):
    lines = reconstruct_lines(rows)
    n_chars = len(rows)
    clean = 0
    max_gap = 0.0
    for bid, ch in lines:
        hs = [int(c["Height"]) for c in ch]
        mh = statistics.median(hs)
        xs = [int(c["X"]) + int(c["Width"]) / 2 for c in ch]
        mw = statistics.median(int(c["Width"]) for c in ch)
        spread = (max(xs) - min(xs)) if len(xs) > 1 else 0
        gaps = [int(b["Y"]) - (int(a["Y"]) + int(a["Height"])) for a, b in zip(ch, ch[1:])]
        g = max(gaps) / mh if gaps else 0
        max_gap = max(max_gap, g)
        if spread <= 0.8 * mw and g <= MAX_GAP_RATIO and len(ch) >= 3:
            clean += len(ch)
    return lines, dict(n_chars=n_chars, n_lines=len(lines), clean_frac=clean / n_chars, max_gap=max_gap)


def main():
    os.makedirs(OUT, exist_ok=True)
    rng = random.Random(SEED)
    chosen = []
    for book in BOOKS:
        zpath = os.path.join(RAW, f"{book}.zip")
        with zipfile.ZipFile(zpath) as z:
            pages = rows_by_page(z, book)
            elig = []
            for img in sorted(pages):
                lines, st = page_stats(pages[img])
                if (st["n_chars"] >= MIN_CHARS and MIN_LINES <= st["n_lines"] <= MAX_LINES
                        and st["clean_frac"] >= MIN_COLUMNS_OK):
                    elig.append((img, lines, st))
            print(book, "pages with annotations:", len(pages), "eligible:", len(elig), file=sys.stderr)
            pick = sorted(rng.sample(elig, PER_BOOK), key=lambda t: t[0])
            for img, lines, st in pick:
                with open(os.path.join(OUT, img + ".jpg"), "wb") as f:
                    f.write(z.read(f"{book}/images/{img}.jpg"))
                ref = [dict(block=b, text=line_text(ch)) for b, ch in lines]
                with open(os.path.join(OUT, img + ".json"), "w", encoding="utf-8") as f:
                    json.dump(dict(image=img, book=book, lines=ref, stats=st), f, ensure_ascii=False, indent=1)
                chosen.append((book, img, st, len(elig), len(pages)))
    with open(os.path.join(HERE, "pages_selected.csv"), "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["page_id", "book_id", "book_title", "source_zip_url", "licence", "n_chars", "n_lines",
                    "eligible_in_book", "annotated_pages_in_book", "seed"])
        for book, img, st, ne, npg in chosen:
            w.writerow([img, book, BOOK_TITLE[book], f"http://codh.rois.ac.jp/char-shape/dataset/v2/{book}.zip",
                        "CC BY-SA 4.0", st["n_chars"], st["n_lines"], ne, npg, SEED])
    print("selected", len(chosen))


if __name__ == "__main__":
    main()
