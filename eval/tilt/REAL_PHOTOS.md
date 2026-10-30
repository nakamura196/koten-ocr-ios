# Real oblique photos: protocol

Purpose: check that the synthetic warps in `manifest.csv` behave like real oblique captures. About 10 photos are
enough for a sanity check (this is not a benchmark by itself).

## What to photograph

Take 3 pages from `pages_selected.csv`, one per book if possible, each with at least 10 lines
(`n_lines` column). Suggested: the first page listed for each book. Note the `page_id` of each.
The pages come from the CODH 日本古典籍くずし字データセット (CC BY-SA 4.0), so printing and photographing them is
allowed; keep the attribution in anything you publish.

1. Print the page image from `data/pages/<page_id>.jpg` (made by `select_pages.py`) on one plain A4 sheet,
   100 % scale (no "fit to page"), portrait, one page per sheet, black and white is fine.
2. Lay the sheet flat on a table with even daylight. No flash. Avoid hard shadows of your hand or phone.
3. With the iPhone camera app (1x lens, no Portrait mode, no night mode), photograph the sheet at four camera
   angles measured from the vertical (the line straight down onto the sheet): about 0, 10, 20 and 30 degrees.
   - Tilt by moving the phone toward you and pointing up at the page, so the far (top) edge of the page is further
     away. This makes the columns converge toward the top, like the `key-up` conditions.
   - Check the angle with a protractor app or by laying a printed protractor next to the sheet. Record the
     nominal angle in the file name.
   - Keep the whole sheet in the frame, about 80 % of the frame height, and the sheet roughly centred.
   - Take one extra shot per page with a small yaw (phone shifted to the right of the sheet, 10 degrees) if you
     want a keystone that is not symmetric.
4. 3 pages x 4 angles = 12 photos. Delete bad ones; about 10 is fine.

## Putting them into the pipeline

1. Export as JPEG (HEIC is not read by the script): AirDrop with "Most Compatible", or
   `sips -s format jpeg IMG_1234.HEIC --out IMG_1234.jpg`. Do not crop or rotate; EXIF orientation is honoured.
2. Rename to `<page_id>__<angle>deg.jpg`, for example `200015843_00031_1__20deg.jpg`, and put the files in
   `eval/tilt/data/real/` (ignored by git; photos are not committed).
3. Register and run:

```
cd eval/tilt
python3 -m venv data/venv && data/venv/bin/pip install -r requirements.txt   # once
data/venv/bin/python -I add_real_photos.py
data/venv/bin/python -I measure.py --manifest real_manifest.csv --deskew off --out results/real_baseline.csv
data/venv/bin/python -I measure.py --manifest real_manifest.csv --deskew on  --out results/real_deskew.csv
data/venv/bin/python -I summarize.py results/real_baseline.csv results/real_deskew.csv
```

## Why the ground truth still applies

The sheet carries exactly the page whose reference lines are in `data/pages/<page_id>.json`, so the photo is scored
against the same reference as its synthetic variants. Nothing else (margins, table) is transcribed; the OCR may
detect text-like marks on the table or sheet edge, which counts as an insertion error, exactly as it would in use.
The printed page is a second-generation copy (printer, paper, phone camera), so the 0 degree photo is the right
anchor: compare each angle with the 0 degree photo of the same page, not with the digital original.

Record in the paper: printer and paper, phone model and iOS version, lighting, and whether the photos were taken
by hand or on a stand.
