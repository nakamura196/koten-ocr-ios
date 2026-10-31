"""Strip-gate candidates (論文 #44, 2026-10-30): compare three changes to the "do not rotate" rule on the tuning set.

Background: on the held-out book 万宝料理秘密箱 the middle strip returned 0.0 deg at +/-8 deg because dark areas outside
the book (picked up as ink) form wide blobs at the top and bottom; cut by vertical strip borders they prefer 0 deg
(papers/44-koten-field/measurements/eval-heldout.md, 2026-10-30 追記).  Candidates, all decision-only (the global angle
is unchanged, so an image is either rotated = gate-off row or declined = no-deskew row, as in tune_gate.py):

  C0  current: left/middle/right thirds of the ink x range, ocrpipe.strips_consistent
  C1  thirds cut along the global angle (coordinate u = x cos A - y sin A instead of x), same consistency rule
  C2  thirds as C0 after removing wide ink components (bbox width > BLOB_W * page width: outside-of-book blobs, frames)
  C3  rotate when C0 is consistent OR every strip scores at least RATIO_T times better at the global angle than at 0

Usage (tuning set only; do not run on manifest_heldout.csv to choose anything):
    data/venv/bin/python -I cand_gate.py features manifest.csv results/cand_gate_features.csv
    data/venv/bin/python -I cand_gate.py eval results/cand_gate_features.csv results/perline.csv results/deskew_perline_nogate.csv
"""
import csv, math, os, sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import cv2  # noqa: E402
import numpy as np  # noqa: E402
from PIL import Image, ImageOps  # noqa: E402
import ocrpipe as op  # noqa: E402

BLOB_WS = (0.10, 0.15, 0.25)


def ink_mask(img):
    """Ink mask exactly as ocrpipe.estimate_skew (before margin and subsampling)."""
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
    return ink & (Y >= margin) & (Y < h - margin) & (X >= margin) & (X < w - margin), w, h


def points(mask, w, h):
    yy, xx = np.nonzero(mask); n = len(xx)
    if n > op.DESKEW_MAX_POINTS:
        idx = np.arange(0, n, n / op.DESKEW_MAX_POINTS).astype(int); idx = idx[idx < n]; xx, yy = xx[idx], yy[idx]
    return xx.astype(np.float32) - np.float32(w) / 2, yy.astype(np.float32) - np.float32(h) / 2


def make_score(bins):
    def score(px_, py_, deg):
        t = deg * math.pi / 180
        u = px_ * np.float32(math.cos(t)) - py_ * np.float32(math.sin(t))
        k = np.clip(np.floor(u + np.float32(bins // 2)).astype(np.int64), 0, bins - 1)
        hst = np.bincount(k, minlength=bins).astype(np.float64)
        return float((hst * hst).sum())
    return score


def search(score, px_, py_):
    """Same grid as ocrpipe.estimate_skew.search."""
    best, ba = -1.0, 0.0
    for k in range(-20, 21):
        sc = score(px_, py_, k * 0.5)
        if sc > best: best, ba = sc, k * 0.5
    c = ba
    for k in range(-5, 6):
        if k == 0: continue
        sc = score(px_, py_, c + k * 0.1)
        if sc > best: best, ba = sc, c + k * 0.1
    return round(ba * 10) / 10


def thirds(key):
    lo, hi = np.percentile(key, [2, 98])
    return [(key >= lo + (hi - lo) * i / 3) & ((key < lo + (hi - lo) * (i + 1) / 3) if i < 2 else (key <= lo + (hi - lo) * (i + 1) / 3))
            for i in range(3)]


def features(img):
    est = op.estimate_skew(img)
    A = est["angle"]
    mask, w, h = ink_mask(img)
    fx, fy = points(mask, w, h)
    bins = int(math.sqrt(w * w + h * h)) + 2
    score = make_score(bins)
    out = dict(angle=A, gain=round(est["gain"], 4), ink=est["ink"])
    out.update({f"c0_{i}": ("" if a is None else a) for i, a in enumerate(est["strips"])})
    if len(fx) < op.DESKEW_MIN_INK:
        return out
    # C1: thirds along the global angle
    t = math.radians(A); u = fx * np.float32(math.cos(t)) - fy * np.float32(math.sin(t))
    for i, m in enumerate(thirds(u)):
        out[f"c1_{i}"] = search(score, fx[m], fy[m]) if int(m.sum()) >= op.DESKEW_MIN_INK else ""
    # C3: per-strip score at the global angle relative to 0 deg (C0 strips)
    for i, m in enumerate(thirds(fx)):
        s0 = score(fx[m], fy[m], 0.0)
        out[f"r3_{i}"] = round(score(fx[m], fy[m], A) / s0, 4) if int(m.sum()) >= op.DESKEW_MIN_INK and s0 > 0 else ""
    # C2: drop wide components
    n, lab, st, _ = cv2.connectedComponentsWithStats(mask.astype(np.uint8), connectivity=8)
    for bw in BLOB_WS:
        wide = np.zeros(n, bool); wide[1:] = st[1:, cv2.CC_STAT_WIDTH] > bw * w
        keep = mask & ~wide[lab]
        gx, gy = points(keep, w, h)
        tag = f"c2w{int(bw * 100)}"
        out[f"{tag}_drop"] = round(1 - keep.sum() / max(1, mask.sum()), 3)
        if len(gx) < op.DESKEW_MIN_INK:
            for i in range(3): out[f"{tag}_{i}"] = ""
            continue
        for i, m in enumerate(thirds(gx)):
            out[f"{tag}_{i}"] = search(score, gx[m], gy[m]) if int(m.sum()) >= op.DESKEW_MIN_INK else ""
    return out


def _feat(r):
    img = ImageOps.exif_transpose(Image.open(os.path.join(HERE, r["image_file"]))).convert("RGB")
    return dict(image_file=r["image_file"], page_id=r["page_id"], condition=r["condition"], **features(img))


def cmd_features(manifest, out):
    import multiprocessing as mp
    rows = list(csv.DictReader(open(manifest, encoding="utf-8")))
    with mp.get_context("spawn").Pool(4) as pool:
        res = list(pool.imap(_feat, rows, chunksize=4))
    keys = []
    for r in res:
        for k in r:
            if k not in keys: keys.append(k)
    with open(out, "w", newline="", encoding="utf-8") as f:
        wr = csv.DictWriter(f, fieldnames=keys, restval=""); wr.writeheader(); wr.writerows(res)
    print(f"wrote {len(res)} rows to {out}", file=sys.stderr)


def fl(v):
    return None if v == "" else float(v)


def base_ok(r):
    return abs(float(r["angle"])) >= op.DESKEW_MIN_ANGLE and float(r["gain"]) >= op.DESKEW_MIN_GAIN and int(r["ink"]) >= op.DESKEW_MIN_INK


def rules():
    c0 = lambda r: op.strips_consistent([fl(r[f"c0_{i}"]) for i in range(3)])
    R = [("gate off", lambda r: True), ("C0 current", c0),
         ("C1 along angle", lambda r: op.strips_consistent([fl(r.get(f"c1_{i}", "")) for i in range(3)]))]
    for bw in BLOB_WS:
        tag = f"c2w{int(bw * 100)}"
        R.append((f"C2 drop wide>{bw}", lambda r, tag=tag: op.strips_consistent([fl(r.get(f"{tag}_{i}", "")) for i in range(3)])))
    for t in (1.0, 1.02, 1.05, 1.1):
        def c3(r, t=t):
            if c0(r): return True
            v = [fl(r.get(f"r3_{i}", "")) for i in range(3)]
            v = [x for x in v if x is not None]
            return len(v) >= 2 and min(v) >= t
        R.append((f"C3 ratio>={t}", c3))
    for t in (1.0, 1.05, 1.1):
        def c3b(r, t=t):
            if c0(r): return True
            v = [fl(r.get(f"r3_{i}", "")) for i in range(3)]
            v = [x for x in v if x is not None]
            return len(v) >= 2 and sum(x >= t for x in v) >= 2
        R.append((f"C3b 2 of 3 ratio>={t}", c3b))
    return R


def cmd_eval(feat, declined_csv, rotated_csv):
    F = list(csv.DictReader(open(feat, encoding="utf-8")))
    dec = {r["image_file"]: r for r in csv.DictReader(open(declined_csv, encoding="utf-8"))}
    rot = {r["image_file"]: r for r in csv.DictReader(open(rotated_csv, encoding="utf-8"))}
    groups = [("all", lambda c: True), ("rot", lambda c: c.startswith("rot")),
              ("rot±8", lambda c: c in ("rot-8.0", "rot+8.0")), ("rot±3..8", lambda c: c in ("rot-3.0", "rot+3.0", "rot-5.0", "rot+5.0", "rot-8.0", "rot+8.0")),
              ("key", lambda c: c.startswith("key")), ("key±3", lambda c: c in ("key-up3", "key-down3")),
              ("curl+light", lambda c: c.startswith("curl") or c.startswith("lightkey"))]
    print("CER % / leak3 (declined images = " + os.path.basename(declined_csv) + ", rotated = " + os.path.basename(rotated_csv) + ")\n")
    print("| rule | " + " | ".join(g for g, _ in groups) + " | declined rot±3..8 | declined key±3 |")
    print("|---" * (len(groups) + 3) + "|")
    for name, ok in rules():
        agg = defaultdict(lambda: [0.0, 0.0, 0.0]); d38 = dk3 = 0
        for r in F:
            go = base_ok(r) and ok(r)
            src = (rot if go else dec)[r["image_file"]]
            c = r["condition"]
            for g, f in groups:
                if f(c):
                    a = agg[g]; a[0] += float(src["edit"]); a[1] += float(src["n_ref"]); a[2] += float(src["leak3"])
            if base_ok(r) and not ok(r):
                d38 += c in ("rot-3.0", "rot+3.0", "rot-5.0", "rot+5.0", "rot-8.0", "rot+8.0")
                dk3 += c in ("key-up3", "key-down3")
        cells = [f"{100 * agg[g][0] / agg[g][1]:.1f} / {int(agg[g][2])}" for g, _ in groups]
        print(f"| {name} | " + " | ".join(cells) + f" | {d38}/180 | {dk3}/60 |")


if __name__ == "__main__":
    if sys.argv[1] == "features":
        cmd_features(sys.argv[2], sys.argv[3])
    else:
        cmd_eval(sys.argv[2], sys.argv[3], sys.argv[4])
