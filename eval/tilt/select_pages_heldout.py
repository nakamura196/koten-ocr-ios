"""Held-out page selection (see HELDOUT.md). Reuses select_pages.py's eligibility functions unchanged.

Books are drawn with random.Random(20261030).sample(sorted candidates, 3); if a drawn book has fewer than 10
eligible pages, the next book is drawn from the remaining candidates with the same RNG (recorded in HELDOUT.md).
Pages: random.Random(20261030).sample(eligible, 10) per book, as in select_pages.py (fresh RNG per run, shared across books).

Input : heldout_candidates.json (candidate ID list, written by the book-list step), data/raw/<book>.zip
Output: data/pages/<page_id>.jpg/.json, pages_selected_heldout.csv
Run:  python -I select_pages_heldout.py
"""
import csv, json, os, random, sys, zipfile
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import select_pages as sp

HERE = sp.HERE
SEED = 20261030
CAND = json.load(open(os.path.join(HERE, "heldout_candidates.json"), encoding="utf-8"))
CANDS = sorted(CAND["cands"])
TITLES = CAND["titles"]


def main():
    os.makedirs(sp.OUT, exist_ok=True)
    book_rng = random.Random(SEED)
    drawn = book_rng.sample(CANDS, 3)
    remaining = [c for c in CANDS if c not in drawn]
    page_rng = random.Random(SEED)
    chosen, books, i = [], [], 0
    log = []
    while len(books) < 3:
        book = drawn[i] if i < len(drawn) else book_rng.sample(remaining, 1)[0]
        if i >= len(drawn):
            remaining.remove(book)
        i += 1
        zpath = os.path.join(sp.RAW, f"{book}.zip")
        if not os.path.exists(zpath):
            print("missing zip", book); sys.exit(1)
        with zipfile.ZipFile(zpath) as z:
            pages = sp.rows_by_page(z, book)
            elig = []
            for img in sorted(pages):
                lines, st = sp.page_stats(pages[img])
                if (st["n_chars"] >= sp.MIN_CHARS and sp.MIN_LINES <= st["n_lines"] <= sp.MAX_LINES
                        and st["clean_frac"] >= sp.MIN_COLUMNS_OK):
                    elig.append((img, lines, st))
            print(book, TITLES[book], "annotated:", len(pages), "eligible:", len(elig), file=sys.stderr)
            log.append((book, len(pages), len(elig)))
            if len(elig) < sp.PER_BOOK:
                print("  -> fewer than 10 eligible: redraw", file=sys.stderr)
                continue
            books.append(book)
            pick = sorted(page_rng.sample(elig, sp.PER_BOOK), key=lambda t: t[0])
            for img, lines, st in pick:
                with open(os.path.join(sp.OUT, img + ".jpg"), "wb") as f:
                    f.write(z.read(f"{book}/images/{img}.jpg"))
                ref = [dict(block=b, text=sp.line_text(ch)) for b, ch in lines]
                with open(os.path.join(sp.OUT, img + ".json"), "w", encoding="utf-8") as f:
                    json.dump(dict(image=img, book=book, lines=ref, stats=st), f, ensure_ascii=False, indent=1)
                chosen.append((book, img, st, len(elig), len(pages)))
    with open(os.path.join(HERE, "pages_selected_heldout.csv"), "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["page_id", "book_id", "book_title", "source_zip_url", "licence", "n_chars", "n_lines",
                    "eligible_in_book", "annotated_pages_in_book", "seed"])
        for book, img, st, ne, npg in chosen:
            w.writerow([img, book, TITLES[book], f"http://codh.rois.ac.jp/char-shape/dataset/v2/{book}.zip",
                        "CC BY-SA 4.0", st["n_chars"], st["n_lines"], ne, npg, SEED])
    print("drawn:", drawn, "used:", books, "log:", log)
    print("selected", len(chosen))


if __name__ == "__main__":
    main()
