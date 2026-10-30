# Tilt / oblique-capture robustness evaluation for KotenOCR

A reproducible dataset and measurement script for how the app's pipeline (RTMDet line detection, PARSeq recognition,
block XY-cut reading order, optional global deskew) copes with rotated and obliquely photographed pages.
Everything here is generated from a public dataset; **no images or transcripts are committed** (`data/` is
git-ignored). The committed files are the scripts, `pages_selected.csv`, `manifest.csv` and the result CSVs.

## Source data

- **Dataset:** 日本古典籍くずし字データセット (Dataset of Pre-Modern Japanese Kuzushiji), v2, ROIS-DS Center for Open Data
  in the Humanities (CODH) / National Institute of Japanese Literature (国文研). doi:10.20676/00000340,
  http://codh.rois.ac.jp/char-shape/
- **Licence:** CC BY-SA 4.0. Required attribution: 『日本古典籍くずし字データセット』（国文研ほか所蔵／CODH加工）.
  The transformed images are adaptations and stay under CC BY-SA 4.0 (this is why they are not committed with the
  repository's own licence; regenerate them with the scripts).
- **Books used** (per-book ZIPs `http://codh.rois.ac.jp/char-shape/dataset/v2/<id>.zip`):
  200015843 日本永代蔵, 200005798 世間胸算用／大晦日ハ一日千金, 200008316 武家義理物語 (all Saikaku, woodblock prints).
- **What the data contains:** page images (spreads already split, rotated upright) and per-character boxes with Unicode
  and a Block ID / Char ID. There are no line-level transcriptions, so lines are rebuilt (below).

### Why this source (and not the NDL data)

The NDL古典籍OCR-Lite models bundled with the app were trained on the NDL みんなで翻刻 line dataset
(https://github.com/ndl-lab/ndl-minhon-ocrdataset, CC BY-SA 4.0; the ndlkotenocr-lite README names it and
`train/README.md` tells you to build the PARSeq training set from it; layout training uses NDL-DocL).
That dataset has line-level text, but the models have seen it, so absolute CER would be inflated by memorisation.
CODH is not listed anywhere as training data for these models.

**Contamination assessment (written down, not proven):**
- Checked: none of the three titles occurs in the `v1_metadata.csv` / `v2_metadata.csv` of ndl-minhon-ocrdataset
  (grep for 永代蔵, 胸算用, 義理物語, 西鶴, 好色一代; no hit, as of 2026-10-29). Those files list the pages used for
  PARSeq training.
- Not checked: whether NDL-DocL (layout/RTMDet training) or any private NDL training data contains other copies of
  these works; whether the PARSeq charset training used other corpora. Other printed editions of the same texts exist
  in NDL Digital Collections, so partial overlap in *text* (not images) cannot be excluded.
- Consequence: absolute CER is meaningful as "on a source not documented as training data", but the headline claim of
  the evaluation is the *change* in CER and leak counts across conditions on identical pages, which is not affected by
  a constant memorisation advantage.

## Page selection (`select_pages.py`, seed 20261029)

Per book, all annotated pages are filtered with criteria that never involve the OCR model:
at least 150 annotated characters; 8 to 20 reconstructed lines; at least 95 % of characters in "clean" lines
(horizontal spread of the line at most 0.8 of the median character width, no gap larger than 1 character height, at
least 3 characters). Spreads are already split in the dataset (`_1` / `_2` suffix = one page).
`random.Random(20261029).sample` picks 10 eligible pages per book (99 / 86 / 121 eligible), giving **30 pages**,
listed in `pages_selected.csv`.

**Reference lines:** the CSV gives characters in reading order inside a Block. A new line starts when the next
character is more than 0.6 median widths to the left and not lower than the previous one. Reference text of a page =
its lines in CODH block order (right to left), concatenated.
Known limits of this reference: CODH unifies kyujitai to shinjitai and variant kana to modern kana, leaves unreadable
characters blank and does not transcribe ruby, while the model emits historical forms and may read ruby. This adds a
constant error at 0 degrees; compare conditions, not absolute values.

## Transforms (`make_variants.py`; seed 20261029; 19 per page, 570 images)

Angle convention as in the app (`Deskew.swift`): positive = page content rotated counter-clockwise on screen.
Padding is paper colour (median of the brightest 40 % of pixels of the page), never black. JPEG quality 92.

| family | conditions | definition |
|---|---|---|
| rotation | rot-8.0, -5.0, -3.0, -1.5, +0.0, +1.5, +3.0, +5.0, +8.0 | whole page rotated, canvas expanded, bicubic. rot+0.0 is the untouched page |
| keystone | key-up1/2/3, key-down1/2/3 | perspective warp; all columns converge to a vanishing point above (up) or below (down) the page on its centre line, chosen so the leftmost/rightmost column leans by -a/+a degrees (a = 1, 2, 3; so columns lean from -a to +a across the page, opposite sign for down). Canvas unchanged, the page shrinks inside it |
| curl | curl2, curl4 | columns bent into a parabola (x' = x + s*4v(1-v)*W, v = y/H); the column tilt is 0 at mid height and +/-2 or +/-4 degrees at the top/bottom edge |
| light+keystone | lightkey-up2, lightkey-down2 | keystone with a = 2 degrees plus a multiplicative brightness gradient from 1.0 to 0.55 along a direction drawn from `Random("<seed>/<page>/<condition>")` |

All parameters (including the drawn gradient direction, the padding colour and the destination quadrilateral) are in
`params_json` of `manifest.csv`, with the source URL, licence, attribution and SHA-256 of each produced file (JPEG bytes depend on the OpenCV build; the parameters are the
authoritative record).

## Measurement (`measure.py`, `ocrpipe.py`, `summarize.py`)

`ocrpipe.py` is a Python port of koten mode (OCREngine.processKoten): optional Deskew, RTMDet (model input
1024x1024, black padding, ImageNet mean/std, score >= 0.3, 2 % vertical box padding, at most 100 boxes), crop, PARSeq
(32x384, vertical crops rotated 90 degrees CCW, greedy decode with NDLmoji.yaml), block XY-cut reading order,
lines joined with newline. ONNX Runtime CPU. Models are read from the main checkout
(`~/git/hi/miyako/koten-ocr-ios/KotenOCR/Models`, override with `--models`); SHA-256 of the models used:
rtmdet-s-1280x1280.onnx f46267754d406431f6e035f9e20b8552af8ff1ab5ca13bcac8f4b1abbd02090c;
parseq-ndl-32x384-tiny-10.onnx 18dbbab16547084cbc18edb4297826f0d46f1853e0d60a7639acab4d5872da5b;
NDLmoji.yaml 775eb37e6b09ad0a97b762d48c916c60e7ce8879a4628ddb190ce037d0a15772.

```
cd eval/tilt
python3 -m venv data/venv && data/venv/bin/pip install -r requirements.txt
data/venv/bin/python -I select_pages.py          # needs data/raw/<book>.zip (URLs above)
data/venv/bin/python -I make_variants.py
data/venv/bin/python -I measure.py --deskew off --per-line off --out results/baseline.csv
data/venv/bin/python -I measure.py --deskew on  --per-line off --out results/deskew.csv
data/venv/bin/python -I summarize.py results/baseline.csv results/deskew.csv
```

**Normalisation:** NFKC, then delete every character in Unicode categories Z (spaces), C (control), P (punctuation) and
S (symbols). Line breaks and spaces therefore never count. No folding of old/new character forms or variant kana.

**Metrics**
- `cer`: Levenshtein(hyp, ref) / len(ref) per page, hypothesis = lines in the app's reading order. The summary
  micro-averages over pages (sum of edits / sum of reference lengths).
- `bag_cer`: reading-order-independent (max(|ref|,|hyp|) - multiset overlap) / |ref|; separates recognition
  errors from ordering errors.
- `leak3` / `leak5`: recognised lines containing a 3-gram (5-gram) that is found in a neighbouring reference line
  (the line the recognised line is assigned to, +/- 1) but not in the assigned line. Assignment = reference line sharing
  most trigrams. Coincidental kana trigrams give a floor, visible in the rot+0.0 row.
- `dup_within`: immediate repeats of a >= 3-character unit inside one line; `dup_cross`: recognised lines (not the
  first) sharing a 5-gram that occurs in more recognised lines than in the reference. Summary column `dup` = sum.

**Switches:** `--deskew on|off`; `--per-line on|off`. Per-line hook: with `--per-line on` the file given by
`--per-line-module` (or `KOTEN_PERLINE_MODULE`) must expose `rectify_line(crop_rgb, box, page) -> crop_rgb`; it is applied
between cropping and PARSeq. `perline_linetilt_adapter.py` wires the Python prototype of branch `line-tilt` (`plan_line`, oriented crops) in; a copy of the
prototype is committed as `linetilt_proto_ocr.py` (provenance in its header; copy of commit 5fb5452's Python mirror, only
the models path became `$KOTEN_MODELS`). `LINETILT_PROTO=/path/to/ocr.py` overrides it. Only its crop step is used, not its
dedupe/garbage filter, so the Python "per-line" configurations differ from the app (which also drops duplicate and
placeholder-only lines).

**Deskew strip gate (added 2026-10-29):** `--strip-gate on|off` (default on). Global deskew additionally estimates the angle on the left,
middle and right thirds of the text area (2nd..98th percentile of the ink x) with the same projection method; it declines
to rotate when max-min of the strip angles exceeds `DESKEW_STRIP_SPREAD` (2.0 degrees) or when two strips have opposite
signs and both exceed `DESKEW_SIGN_NOISE` (0.5 degrees). `tune_gate.py` derives the CER at other thresholds from the
baseline and old-gate runs without re-running OCR (`results/gate_tuning.md`, `results/strip_angles.csv`). `summarize4.py`
makes the four-configuration table with bootstrap CIs (`results/summary4.md`, `results/summary4_ci.csv`).

## Differences between `ocrpipe.py` and the Swift app

1. Image resampling: Core Graphics (`interpolationQuality = .high`) in Swift; OpenCV INTER_AREA (down) / INTER_CUBIC
   (up) here. Both for the detector's 1024 square and for the PARSeq 384x32 resize. Small numeric differences in the
   tensors; not bit-exact.
2. Deskew rotation: Core Graphics high-quality interpolation vs PIL bicubic; deskew working image downscale
   (CG medium vs OpenCV INTER_AREA). The estimator itself (adaptive threshold, 0.5 / 0.1 degree search, gains,
   margins, paper colour) is a line-by-line port, but its point subsampling uses numpy indices.
3. Images are decoded by PIL/OpenCV; the app receives a CGImage from the camera/photo library (colour management,
   EXIF orientation are handled by iOS). Synthetic JPEGs have no colour profile.
4. Recognition is sequential here; the app runs batches of 4 in parallel (no effect on results).
5. Reading order: same algorithm and float32 grid arithmetic; Swift's `sort` is not stable, Python's is (only matters
   for exactly tied keys). Swift `Int(Float)` truncation is mirrored with `int()`.
6. NDL (modern print) mode is not covered; only the koten mode, which the app uses by default for kuzushiji.
7. ONNX Runtime 1.19.2 CPU here; the app uses its own bundled ONNX Runtime build (CPU, no CoreML options set).
8. Not verified against the iOS app on the same images: no run of the Swift binary was done for this commit. Agreement
   was only sanity-checked (reasonable CER at 0 degrees); treat absolute numbers as "the Python port".

## Real photos

See `REAL_PHOTOS.md`.

## Results (30 pages x 19 conditions = 570 images, run 2026-10-29)

Python port of koten mode, ONNX Runtime 1.19.2 CPU. `results/baseline.csv` = deskew off, `results/deskew.csv` = deskew on, per-line off. CER is micro-averaged over the 30 pages; 'dup' = dup_within + dup_cross. Single run, no confidence intervals; differences of about 1 point are within what 30 pages can resolve poorly. The 12-13 % CER at rot+0.0 is mostly the reference/model mismatch described above (old vs new character forms, variant kana, ruby), not a recognition failure.

| condition | pages | baseline CER% | baseline bagCER% | baseline leak3 | baseline leak5 | baseline dup | deskew CER% | deskew bagCER% | deskew leak3 | deskew leak5 | deskew dup |
|---|---|---|---|---|---|---|---|---|---|---|---|
| rot-8.0 | 30 | 84.5 | 43.3 | 195 | 94 | 105 | 9.2 | 8.6 | 0 | 0 | 5 |
| rot-5.0 | 30 | 56.1 | 44.4 | 148 | 75 | 134 | 9.3 | 8.8 | 0 | 0 | 3 |
| rot-3.0 | 30 | 17.6 | 16.5 | 1 | 0 | 24 | 10.6 | 10.2 | 0 | 0 | 8 |
| rot-1.5 | 30 | 12.6 | 12.0 | 0 | 0 | 10 | 11.6 | 11.0 | 0 | 0 | 5 |
| rot+0.0 | 30 | 12.9 | 12.3 | 0 | 0 | 3 | 12.8 | 12.2 | 0 | 0 | 5 |
| rot+1.5 | 30 | 12.2 | 11.8 | 0 | 0 | 9 | 12.5 | 11.7 | 0 | 0 | 5 |
| rot+3.0 | 30 | 18.1 | 16.7 | 1 | 0 | 30 | 10.6 | 10.1 | 0 | 0 | 6 |
| rot+5.0 | 30 | 70.5 | 51.6 | 174 | 85 | 158 | 9.4 | 8.8 | 0 | 0 | 3 |
| rot+8.0 | 30 | 91.0 | 43.7 | 157 | 71 | 76 | 9.0 | 8.4 | 0 | 0 | 1 |
| key-up1 | 30 | 12.6 | 12.0 | 0 | 0 | 5 | 12.7 | 12.0 | 0 | 0 | 3 |
| key-up2 | 30 | 12.5 | 11.8 | 0 | 0 | 4 | 14.1 | 13.2 | 0 | 0 | 9 |
| key-up3 | 30 | 12.8 | 12.0 | 0 | 0 | 8 | 22.8 | 18.6 | 31 | 15 | 29 |
| key-down1 | 30 | 11.2 | 10.7 | 0 | 0 | 5 | 11.7 | 11.2 | 0 | 0 | 5 |
| key-down2 | 30 | 10.1 | 9.6 | 0 | 0 | 2 | 12.5 | 11.7 | 0 | 0 | 5 |
| key-down3 | 30 | 10.6 | 9.8 | 0 | 0 | 1 | 22.6 | 19.1 | 28 | 5 | 26 |
| curl2 | 30 | 13.0 | 12.4 | 0 | 0 | 4 | 13.1 | 12.6 | 0 | 0 | 3 |
| curl4 | 30 | 11.6 | 11.1 | 1 | 0 | 3 | 11.9 | 11.4 | 1 | 0 | 3 |
| lightkey-up2 | 30 | 10.0 | 9.5 | 0 | 0 | 2 | 11.2 | 10.3 | 0 | 0 | 6 |
| lightkey-down2 | 30 | 8.7 | 8.2 | 0 | 0 | 2 | 11.8 | 10.9 | 0 | 0 | 3 |

| family | baseline CER% / leak3 | deskew CER% / leak3 |
|---|---|---|
| rotation | 41.7 / 676 | 10.6 / 0 |
| keystone | 11.6 / 0 | 16.1 / 59 |
| curl | 12.3 / 1 | 12.5 / 1 |
| light+keystone | 9.4 / 0 | 11.5 / 0 |

Observations (measured, not interpreted beyond the numbers):
- Without deskew, rotation is harmless up to about 1.5 degrees, degrades at 3 (CER 17.6-18.1 vs 12.9) and collapses at 5-8 (56-91 %, with 148-195 leaked lines per condition at 5-8 degrees).
- With deskew the rotated pages sit at 9-12 % CER with no leaks; the estimated angle averaged -7.83 for rot-8.0 and +8.14 for rot+8.0.
- Keystone up to +/-3 degrees at the page edge did not hurt the baseline (CER 10-13 %, no leaks). Deskew made keystone 3 worse (22.8 / 22.6 % CER, 31 / 28 leaked lines): one global angle cannot fit columns leaning in opposite directions.
- Curl (max tilt 2 / 4 degrees) and light+keystone were not harmful at these strengths.
- Per-line hook: the full per-line runs are in the "Results with the strip gate" section below.

## Results with the strip gate (30 pages x 19 conditions, run 2026-10-29)

Configurations: baseline (`results/baseline.csv`); deskew with the strip gate (`deskew.csv`); per-line only (`perline.csv`);
deskew + per-line (`deskew_perline.csv`). `deskew_oldgate.csv` is the first run above (no strip check). Full table with 95 %
bootstrap CIs of the CER difference to the baseline (paired over the 30 pages, 10 000 resamples) in `results/summary4.md`;
gate threshold sweep in `results/gate_tuning.md`. The `*.hyp.jsonl` files (recognised text) are git-ignored.
