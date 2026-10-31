# Verification set for strip-gate candidates (30 pages, 19 conditions, 570 images)

Purpose: test the strip-gate candidates of `cand_gate.py` (C0 current, C1, C2, C3, C3b) on pages that were used neither for
tuning (`pages_selected.csv`, three Saikaku books) nor for the held-out evaluation (`HELDOUT.md`). C3b's form was added after
looking at the held-out book 万宝料理秘密箱, so held-out cannot support it; this set can.
Source and licence as in `HELDOUT.md` (日本古典籍くずし字データセット v2, CC BY-SA 4.0; `data/` is git-ignored).

## Rule (2026-10-30)

Same as `HELDOUT.md` with two changes only:
1. Candidates = the 18 of `heldout_candidates.json` minus the three held-out books (200025191, 200014740, 200021712) = 15.
2. Seed 20261031 (book draw, redraws, page draw and per-image transform RNG), instead of 20261030.
Redraws continue the same book RNG, as in `HELDOUT.md`. Comparison rows and the decision-only evaluation are those of
`cand_gate.py` (thresholds unchanged from `results/cand_gate_tuning.md`).

Process note: the three first-drawn book IDs (and the next redraw) were printed once by a one-line preview before this file
was written. The seed and rule had already been chosen; no OCR output of these books had been seen.

## Draw result

Drawn first: 傾城買四十八手, 椿説弓張月, 伊曾保物語 (200021086). Four redraws were needed.

| book | id | annotated pages | eligible pages | used |
|---|---|---|---|---|
| 傾城買四十八手 | 200005598 | 95 | 3 | 0 (redrawn) |
| 椿説弓張月 | 200004148 | 124 | 38 | 10 |
| 伊曾保物語 | 200021086 | 60 | 5 | 0 (redrawn) |
| 日用惣菜俎不時珍客即席庖丁 | 200021853 | 77 | 1 | 0 (redrawn) |
| 曾我物語 | 200017458 | 78 | 33 | 10 |
| おらが春 | 200003967 | 73 | 1 | 0 (redrawn) |
| 養蚕秘録 | 200021660 | 169 | 26 | 10 |

## Reproduce

```
cd eval/tilt
# download https://codh.rois.ac.jp/char-shape/dataset/v2/<id>.zip (https; http returns a 301 page) for the 7 books above into data/raw/
data/venv/bin/python -I select_pages_verify.py    # pages_selected_verify.csv
data/venv/bin/python -I make_variants_verify.py   # manifest_verify.csv, data/variants_verify/
data/venv/bin/python -I measure.py --manifest manifest_verify.csv --deskew off --per-line on --per-line-module perline_linetilt_adapter.py --out results/verify_perline.csv --workers 6
data/venv/bin/python -I measure.py --manifest manifest_verify.csv --deskew on --strip-gate off --per-line on --per-line-module perline_linetilt_adapter.py --out results/verify_deskew_perline_nogate.csv --workers 6
data/venv/bin/python -I measure.py --manifest manifest_verify.csv --deskew on --strip-gate on --per-line on --per-line-module perline_linetilt_adapter.py --out results/verify_deskew_perline.csv --workers 6   # check of the decision-only C0 row
data/venv/bin/python -I cand_gate.py features manifest_verify.csv results/verify_cand_gate_features.csv
data/venv/bin/python -I cand_gate.py eval results/verify_cand_gate_features.csv results/verify_perline.csv results/verify_deskew_perline_nogate.csv > results/cand_gate_verify.md
```
