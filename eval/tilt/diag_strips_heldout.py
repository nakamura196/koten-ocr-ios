"""Diagnostic only (no thresholds are changed): why the strip gate refused to rotate 万宝料理秘密箱 pages at ±8°.

Part 1: global and left/middle/right strip angles (as ocrpipe.estimate_skew) for the 10 pages at rot+0, rot-8, rot+8.
Part 2: projection score of the middle strip at -8..+8 (relative to 0°), split into the central rows (|y| < 0.3h)
and the outer rows (|y| >= 0.3h), on rot-8.0.  Writes results/heldout_manpo_strips.csv and prints part 2.
Usage: data/venv/bin/python -I diag_strips_heldout.py
"""
import csv, math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from PIL import Image
import ocrpipe as op

PAGES = ["00011_1", "00014_2", "00035_2", "00042_2", "00053_2", "00056_1", "00056_2", "00064_1", "00064_2", "00074_2"]
F = "data/variants_heldout/200021712_{}__{}.jpg"


def ink_points(img):
    """Same ink mask, margin and subsampling as estimate_skew; returns centred x, y and the work size."""
    px = op._downscale(img); h, w = px.shape[:2]
    g = ((px[..., 0].astype(np.uint32) * 299 + px[..., 1].astype(np.uint32) * 587
          + px[..., 2].astype(np.uint32) * 114) // 1000).astype(np.int64)
    radius = max(7, max(w, h) // 40); margin = max(2, int(0.015 * max(w, h)))
    ii = np.zeros((h + 1, w + 1), dtype=np.int64); ii[1:, 1:] = g.cumsum(0).cumsum(1)
    ys, xs = np.arange(h), np.arange(w)
    y0, y1 = np.clip(ys - radius, 0, h), np.clip(ys + radius + 1, 0, h)
    x0, x1 = np.clip(xs - radius, 0, w), np.clip(xs + radius + 1, 0, w)
    S = ii[y1][:, x1] - ii[y0][:, x1] - ii[y1][:, x0] + ii[y0][:, x0]
    area = ((y1 - y0)[:, None] * (x1 - x0)[None, :]).astype(np.int64)
    ink = g * area * 100 < S * 85 - 400 * area
    Y, X = np.mgrid[0:h, 0:w]
    yy, xx = np.nonzero(ink & (Y >= margin) & (Y < h - margin) & (X >= margin) & (X < w - margin))
    n = len(xx)
    if n > op.DESKEW_MAX_POINTS:
        idx = np.arange(0, n, n / op.DESKEW_MAX_POINTS).astype(int); idx = idx[idx < n]; xx, yy = xx[idx], yy[idx]
    return xx - w / 2, yy - h / 2, w, h


def score(fx, fy, deg, bins):
    t = math.radians(deg); u = fx * math.cos(t) - fy * math.sin(t)
    k = np.clip(np.floor(u + bins // 2).astype(int), 0, bins - 1)
    hst = np.bincount(k, minlength=bins).astype(float)
    return float((hst * hst).sum())


rows = []
for p in PAGES:
    for c in ["rot+0.0", "rot-8.0", "rot+8.0"]:
        e = op.estimate_skew(Image.open(F.format(p, c)))
        rows.append(dict(page=p, condition=c, angle=e["angle"], gain=round(e["gain"], 4), ink=e["ink"],
                         strip_l=e["strips"][0], strip_m=e["strips"][1], strip_r=e["strips"][2],
                         consistent=op.strips_consistent(e["strips"])))
with open("results/heldout_manpo_strips.csv", "w", newline="") as fh:
    wr = csv.DictWriter(fh, fieldnames=list(rows[0])); wr.writeheader(); wr.writerows(rows)

print("page part n_points  score(deg)/score(0) for deg in -8 -4 0 4 8  (rot-8.0, middle strip)")
for p in PAGES:
    fx, fy, w, h = ink_points(Image.open(F.format(p, "rot-8.0")))
    bins = int(math.sqrt(w * w + h * h)) + 2
    lo, hi = np.percentile(fx, [2, 98]); a, b = lo + (hi - lo) / 3, lo + (hi - lo) * 2 / 3
    m = (fx >= a) & (fx < b)
    for name, mm in [("all", m), ("central", m & (np.abs(fy) < 0.3 * h)), ("outer", m & (np.abs(fy) >= 0.3 * h))]:
        s0 = score(fx[mm], fy[mm], 0, bins)
        print(p, name, int(mm.sum()), " ".join(f"{score(fx[mm], fy[mm], d, bins) / s0:.3f}" for d in (-8, -4, 0, 4, 8)))
