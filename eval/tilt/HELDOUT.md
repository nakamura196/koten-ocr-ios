# Held-out evaluation set (30 pages, 19 conditions, 570 images)

Purpose: a second page set, disjoint from the 30 pages on which the deskew strip-gate threshold was tuned
(`pages_selected.csv`, three Saikaku books). Same dataset, same 19 transforms and parameters as `make_variants.py`.
Nothing here looked at any OCR output; selection uses only site metadata and the eligibility criteria of `select_pages.py`.

Source: 日本古典籍くずし字データセット v2 (CODH / 国文研), doi:10.20676/00000340, http://codh.rois.ac.jp/char-shape/ ,
CC BY-SA 4.0. Attribution: 『日本古典籍くずし字データセット』（国文研ほか所蔵／CODH加工）. The transformed images are adaptations
and stay under CC BY-SA 4.0; they are not committed (`data/` is git-ignored). Regenerate them with the scripts below.

## Rule (fixed before drawing, 2026-10-30)

1. Book list: http://codh.rois.ac.jp/char-shape/book/ (41 books). Printed/manuscript from the 国文研 metadata of each book
   (http://codh.rois.ac.jp/pmjt/book/<id>/, field 刊写の別 and 注記).
2. Exclude: the four Saikaku titles (the three used for tuning plus 好色一代男 200003076), books with 刊写の別 = 写
   (manuscript), a movable-type print (注記 says 古活字版; the aim is woodblock prints), and any book whose title (or either
   half of a 「A／B」 title) occurs in `data/minhon_v1_metadata.csv` / `data/minhon_v2_metadata.csv` (substring match, so it is conservative).
   No book was excluded or kept because its printed/manuscript status was unclear: all 41 have an explicit 刊 or 写.
   Caveat: 刊 also covers non-woodblock prints in principle; only the one book whose note says 古活字版 was detected and dropped.
3. Candidates = sorted IDs (18, in `heldout_candidates.json`). `random.Random(20261030).sample(candidates, 3)`.
   Redraw (if a drawn book has < 10 eligible pages): `book_rng.sample(remaining, 1)` continuing the same RNG.
4. Pages: eligibility as `select_pages.py` (>=150 chars, 8-20 lines, >=95 % clean-line characters; functions imported, not modified);
   `random.Random(20261030).sample(eligible, 10)` per book (one RNG shared across the books in drawing order, as in the original).
5. Transforms: `make_variants.py` functions imported unchanged; per-image RNG `Random("20261030/<page>/<condition>")`.

## Draw result

Drawn first: 仁勢物語 (200025191), 雨月物語 (200014740), 玉くしげ (200018243).
**Redraw happened:** 玉くしげ had only 7 eligible pages (73 annotated), so the next book from the same RNG was used:
万宝料理秘密箱 (200021712). 玉くしげ was downloaded and evaluated for eligibility only (no pages used).

| book | id | annotated pages | eligible pages | used |
|---|---|---|---|---|
| 仁勢物語 | 200025191 | 94 | 57 | 10 |
| 雨月物語 | 200014740 | 154 | 51 | 10 |
| 玉くしげ | 200018243 | 73 | 7 | 0 (redrawn, < 10 eligible) |
| 万宝料理秘密箱 | 200021712 | 158 | 15 | 10 |

## Exclusions (23 of 41)

| id | title | reason |
|---|---|---|
| 100241706 | 虚南留別志 | title in NDL minhon metadata |
| 100249371 | 鼎左秘録 | title in NDL minhon metadata |
| 100249376 | 御前菓子秘伝抄 | title in NDL minhon metadata |
| 100249476 | 飯百珍伝 | title in NDL minhon metadata |
| 100249537 | 料理珍味集 | title in NDL minhon metadata |
| 200003076 | 好色一代男 | Saikaku |
| 200003803 | 源氏物語 | title in NDL minhon metadata |
| 200005798 | 世間胸算用／大晦日ハ一日千金 | Saikaku |
| 200006663 | ぢぐち | title in NDL minhon metadata |
| 200006665 | 吉利支丹物語 | title in NDL minhon metadata |
| 200008316 | 武家義理物語 | Saikaku |
| 200010454 | 源氏物語 | manuscript (刊写の別=写); title in NDL minhon metadata |
| 200015843 | 日本永代蔵 | Saikaku |
| 200020019 | 竹斎 | title in NDL minhon metadata |
| 200021071 | 伊曾保物語 | movable-type print (古活字版), not woodblock |
| 200021637 | 当世料理 | title in NDL minhon metadata |
| 200021644 | 菓子話船橋 | title in NDL minhon metadata |
| 200021763 | 膳部料理抄 | manuscript (刊写の別=写) |
| 200021802 | 料理物語 | title in NDL minhon metadata |
| 200021851 | かてもの | title in NDL minhon metadata |
| 200021869 | 料理方心得之事 | manuscript (刊写の別=写) |
| 200021925 | 新編異国料理 | title in NDL minhon metadata |
| 200022050 | 料理秘伝抄 | title in NDL minhon metadata |

## Candidates (18)

100249416 餅菓子即席／手製集, 200003967 おらが春, 200004107 二人比丘尼, 200004148 椿説弓張月, 200005598 傾城買四十八手, 200008003 歌学提要, 200014685 南総里見八犬伝, 200014740 雨月物語, 200015779 浮世風呂, 200017458 曾我物語, 200018243 玉くしげ, 200019865 女郎花物語, 200021063 うすゆき物語, 200021086 伊曾保物語, 200021660 養蚕秘録, 200021712 万宝料理秘密箱, 200021853 日用惣菜俎不時珍客即席庖丁, 200025191 仁勢物語


## The 30 pages

- 200025191 仁勢物語: 200025191_00007_2, 200025191_00020_2, 200025191_00022_1, 200025191_00028_2, 200025191_00031_2, 200025191_00047_1, 200025191_00047_2, 200025191_00049_1, 200025191_00050_1, 200025191_00058_2
- 200014740 雨月物語: 200014740_00025_1, 200014740_00028_1, 200014740_00028_2, 200014740_00040_1, 200014740_00041_1, 200014740_00050_2, 200014740_00061_1, 200014740_00080_2, 200014740_00082_1, 200014740_00087_1
- 200021712 万宝料理秘密箱: 200021712_00011_1, 200021712_00014_2, 200021712_00035_2, 200021712_00042_2, 200021712_00053_2, 200021712_00056_1, 200021712_00056_2, 200021712_00064_1, 200021712_00064_2, 200021712_00074_2

## Reproduce

```
cd eval/tilt
# download http://codh.rois.ac.jp/char-shape/dataset/v2/<id>.zip for 200025191, 200014740, 200018243, 200021712 into data/raw/
data/venv/bin/python -I select_pages_heldout.py     # pages_selected_heldout.csv, data/pages/<page_id>.jpg/.json
data/venv/bin/python -I make_variants_heldout.py    # manifest_heldout.csv, data/variants_heldout/
```

Original outputs (`pages_selected.csv`, `manifest.csv`, `data/variants/`, `results/`) are not touched. Page-ID prefixes are book
IDs, so `data/pages/` holds both sets without collision. Limits: contamination check is by title only (as in README); the
reference text has the same kyujitai/variant-kana mismatch as the original set.
