"""Step 2: make the tilt / oblique-capture variants of every selected page and write manifest.csv.

Input : data/pages/*.jpg + *.json (from select_pages.py), pages_selected.csv
Output: data/variants/<page_id>__<condition>.jpg   (not committed)
        manifest.csv                                (committed: source, licence, attribution, transform + parameters)

Angle convention (same as Deskew.swift): +angle = page content rotated COUNTER-CLOCKWISE on screen,
i.e. a vertical column then runs top-left -> bottom-right:  x = x0 + y * tan(angle).

Run:  python -I make_variants.py
"""
import csv
import hashlib
import json
import math
import os
import random

import cv2
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
PAGES = os.path.join(HERE, "data", "pages")
OUT = os.path.join(HERE, "data", "variants")
SEED = 20261029
JPEG_QUALITY = 92

ROT_ANGLES = [-8, -5, -3, -1.5, 0, 1.5, 3, 5, 8]
KEY_EDGE_LEAN = [1.0, 2.0, 3.0]        # columns at the page edges lean by +/- this many degrees
CURL_MAX_TILT = [2.0, 4.0]             # column tilt at top/bottom edge of the bowed page
LIGHT_KEY_LEAN = 2.0
LIGHT_DARKEST = 0.55                   # brightness multiplier at the dark side of the gradient

ATTRIBUTION = ("『日本古典籍くずし字データセット』（国文研ほか所蔵／CODH加工） doi:10.20676/00000340, "
               "CC BY-SA 4.0; transformed (rotated/warped/shaded) by this repository's eval/tilt scripts")


def paper_colour(img):
    """Median colour of the brightest 40% of pixels (paper). Used as the padding colour."""
    g = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    thr = np.percentile(g, 60)
    m = g >= thr
    return tuple(int(np.median(img[..., c][m])) for c in range(3))   # BGR


def rotate(img, deg_ccw, pad):
    h, w = img.shape[:2]
    t = math.radians(deg_ccw)
    nw = int(math.ceil(abs(w * math.cos(t)) + abs(h * math.sin(t))))
    nh = int(math.ceil(abs(w * math.sin(t)) + abs(h * math.cos(t))))
    M = cv2.getRotationMatrix2D((w / 2, h / 2), deg_ccw, 1.0)    # cv2: positive = counter-clockwise
    M[0, 2] += nw / 2 - w / 2
    M[1, 2] += nh / 2 - h / 2
    return cv2.warpAffine(img, M, (nw, nh), flags=cv2.INTER_CUBIC, borderMode=cv2.BORDER_CONSTANT, borderValue=pad)


def keystone(img, edge_lean_deg, vanishing, pad):
    """Perspective warp simulating an oblique shot: all columns converge to a vanishing point on the
    vertical centre line.  vanishing='up' -> left-edge column leans -a, right-edge column +a (top narrower);
    'down' flips the sign.  Canvas size is unchanged (the page shrinks inside it, padded with paper)."""
    h, w = img.shape[:2]
    a = math.radians(edge_lean_deg)
    d_plus = (w / 2) / math.tan(a)               # distance from the page centre-line to the vanishing point
    d = d_plus - h / 2                           # distance from vertical centre to V along the axis
    k = (d - h / 2) / (d + h / 2)                # width ratio of the far edge
    cx = w / 2
    src = np.float32([[0, 0], [w, 0], [w, h], [0, h]])
    if vanishing == "up":      # top edge is the far edge
        dst = np.float32([[cx - cx * k, 0], [cx + cx * k, 0], [w, h], [0, h]])
        # keep vertical extent: also shrink height slightly so the page stays inside; no extra change
    else:
        dst = np.float32([[0, 0], [w, 0], [cx + cx * k, h], [cx - cx * k, h]])
    H = cv2.getPerspectiveTransform(src, dst)
    return cv2.warpPerspective(img, H, (w, h), flags=cv2.INTER_CUBIC, borderMode=cv2.BORDER_CONSTANT, borderValue=pad), dict(
        edge_lean_deg=edge_lean_deg, vanishing=vanishing, far_edge_width_ratio=round(k, 6),
        dst_quad=[[round(float(x), 2), round(float(y), 2)] for x, y in dst])


def curl(img, max_tilt_deg, pad):
    """Page bow: every column is bent into a parabola, x' = x + s*4v(1-v)*W with v=y/H.
    The column tilt is 0 at mid-height and +/- max_tilt_deg at top/bottom."""
    h, w = img.shape[:2]
    s = math.tan(math.radians(max_tilt_deg)) * h / (4 * w)
    amp = s * w
    padx = int(math.ceil(amp)) + 2
    big = cv2.copyMakeBorder(img, 0, 0, padx, padx, cv2.BORDER_CONSTANT, value=pad)
    H2, W2 = big.shape[:2]
    ys, xs = np.mgrid[0:H2, 0:W2].astype(np.float32)
    v = ys / H2
    disp = amp * 4 * v * (1 - v)
    out = cv2.remap(big, xs - disp.astype(np.float32), ys, cv2.INTER_CUBIC, borderMode=cv2.BORDER_CONSTANT, borderValue=pad)
    return out, dict(max_tilt_deg=max_tilt_deg, bow_amplitude_px=round(amp, 2), pad_x=padx)


def light(img, rng):
    """Multiplicative brightness gradient along a random direction: 1.0 at one side to LIGHT_DARKEST at the other."""
    h, w = img.shape[:2]
    theta = rng.uniform(0, 360)
    ux, uy = math.cos(math.radians(theta)), math.sin(math.radians(theta))
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    proj = (xs - w / 2) * ux + (ys - h / 2) * uy
    t = (proj - proj.min()) / (proj.max() - proj.min())
    f = 1.0 - (1.0 - LIGHT_DARKEST) * t
    out = np.clip(img.astype(np.float32) * f[..., None], 0, 255).astype(np.uint8)
    return out, dict(gradient_direction_deg=round(theta, 2), darkest_factor=LIGHT_DARKEST)


def conditions():
    for a in ROT_ANGLES:
        yield f"rot{a:+.1f}", "rotation", dict(rotate_ccw_deg=a)
    for v in ("up", "down"):
        for a in KEY_EDGE_LEAN:
            yield f"key-{v}{a:.0f}", "keystone", dict(vanishing=v, edge_lean_deg=a)
    for a in CURL_MAX_TILT:
        yield f"curl{a:.0f}", "curl", dict(max_tilt_deg=a)
    for v in ("up", "down"):
        yield f"lightkey-{v}{LIGHT_KEY_LEAN:.0f}", "light+keystone", dict(vanishing=v, edge_lean_deg=LIGHT_KEY_LEAN)


def apply(img, family, p, pad, rng):
    extra = {}
    if family == "rotation":
        out = rotate(img, p["rotate_ccw_deg"], pad) if p["rotate_ccw_deg"] != 0 else img.copy()
    elif family == "keystone":
        out, extra = keystone(img, p["edge_lean_deg"], p["vanishing"], pad)
    elif family == "curl":
        out, extra = curl(img, p["max_tilt_deg"], pad)
    else:
        out, extra = keystone(img, p["edge_lean_deg"], p["vanishing"], pad)
        out, e2 = light(out, rng)
        extra.update(e2)
    return out, extra


def main():
    os.makedirs(OUT, exist_ok=True)
    sel = list(csv.DictReader(open(os.path.join(HERE, "pages_selected.csv"), encoding="utf-8")))
    rows = []
    for s in sel:
        pid = s["page_id"]
        src = os.path.join(PAGES, pid + ".jpg")
        img = cv2.imread(src, cv2.IMREAD_COLOR)
        pad = paper_colour(img)
        for name, family, p in conditions():
            rng = random.Random(f"{SEED}/{pid}/{name}")
            out, extra = apply(img, family, p, pad, rng)
            fn = f"{pid}__{name}.jpg"
            path = os.path.join(OUT, fn)
            cv2.imwrite(path, out, [cv2.IMWRITE_JPEG_QUALITY, JPEG_QUALITY])
            sha = hashlib.sha256(open(path, "rb").read()).hexdigest()
            params = dict(p, **extra)
            rows.append(dict(
                image_file=f"data/variants/{fn}", page_id=pid, book_id=s["book_id"], book_title=s["book_title"],
                source_url=s["source_zip_url"], source_member=f"{s['book_id']}/images/{pid}.jpg",
                licence="CC BY-SA 4.0", attribution=ATTRIBUTION, condition=name, family=family,
                params_json=json.dumps(params, ensure_ascii=False, sort_keys=True),
                pad_rgb="%d,%d,%d" % (pad[2], pad[1], pad[0]), seed=SEED,
                src_w=img.shape[1], src_h=img.shape[0], out_w=out.shape[1], out_h=out.shape[0], sha256=sha))
    cols = list(rows[0].keys())
    with open(os.path.join(HERE, "manifest.csv"), "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=cols)
        w.writeheader()
        w.writerows(rows)
    print("wrote", len(rows), "images")


if __name__ == "__main__":
    main()
