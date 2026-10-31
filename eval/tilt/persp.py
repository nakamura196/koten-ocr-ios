"""Four-corner perspective correction before OCR (論文 #44, 2026-10-30): a check of the idea "undo the keystone with
a homography first, then the strip gate may be unnecessary".

The synthetic variants pad the warped-away area with the paper colour, so the outer page edge is almost invisible.
The printed frame (匡郭) is visible and is a rectangle on the page, so it stands in for the page's four corners:
outermost long straight lines -> four corners -> homography that maps it to an axis-aligned rectangle
(the whole image is warped, nothing is cropped).  If no plausible quadrilateral is found the image is left unchanged.
This is the same idea as the iOS document-rectangle detection + perspective correction, not the same code.

Usage (tuning set first; do not choose anything on manifest_heldout.csv / manifest_verify.csv):
    data/venv/bin/python -I persp.py manifest.csv manifest_persp.csv data/variants_persp results/persp_detect.csv
then measure.py --manifest manifest_persp.csv as usual.
"""
import csv, json, math, os, sys
import cv2
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
MIN_AREA = 0.25      # quad area / image area
MAX_SIDE_DEV = 15.0  # degrees a side may deviate from horizontal / vertical


def order(pts):
    pts = np.asarray(pts, np.float32).reshape(4, 2)
    s, d = pts.sum(1), pts[:, 0] - pts[:, 1]
    return np.float32([pts[s.argmin()], pts[d.argmax()], pts[s.argmax()], pts[d.argmin()]])  # TL TR BR BL


def _intersect(hl, vl):
    """hl: y = a x + b, vl: x = c y + d."""
    a, b = hl; c, d = vl
    y = (a * d + b) / (1 - a * c)
    return [c * y + d, y]


def detect(img):
    """Return (quad TL,TR,BR,BL in full-res pixels or None, reason).

    Long straight ink segments (frame lines, page edges) are found with a probabilistic Hough transform; the outermost
    near-horizontal and near-vertical segments give four lines whose crossings are the corners.  Each of those lines is
    straight on the original page, so the quad maps to a rectangle even when it mixes the frame and the page edge.
    (First try, 2026-10-30: convex hull of the largest ink component reduced to 4 points; rejected after looking at
    the output: the hull also takes in the dark strip at the page edge, the corners land off the frame and the page
    is sheared instead of straightened.)"""
    h, w = img.shape[:2]
    sc = 1200 / max(h, w)
    g = cv2.cvtColor(cv2.resize(img, (int(w * sc), int(h * sc)), interpolation=cv2.INTER_AREA), cv2.COLOR_BGR2GRAY)
    H, W = g.shape
    ink = cv2.adaptiveThreshold(g, 255, cv2.ADAPTIVE_THRESH_MEAN_C, cv2.THRESH_BINARY_INV, 31, 15)
    segs = cv2.HoughLinesP(ink, 1, np.pi / 720, 150, minLineLength=int(0.3 * min(H, W)), maxLineGap=15)
    if segs is None:
        return None, "no lines"
    hor, ver = [], []
    for x1, y1, x2, y2 in segs.reshape(-1, 4).astype(float):
        ang = math.degrees(math.atan2(y2 - y1, x2 - x1)) % 180
        if min(ang, 180 - ang) <= MAX_SIDE_DEV and abs(x2 - x1) >= 0.4 * W:
            a = (y2 - y1) / (x2 - x1); hor.append((a, y1 - a * x1))
        elif abs(ang - 90) <= MAX_SIDE_DEV and abs(y2 - y1) >= 0.4 * H:
            c = (x2 - x1) / (y2 - y1); ver.append((c, x1 - c * y1))
    if len(hor) < 2 or len(ver) < 2:
        return None, "too few lines"
    hy = lambda l: l[0] * W / 2 + l[1]
    vx = lambda l: l[0] * H / 2 + l[1]
    top, bot = min(hor, key=hy), max(hor, key=hy)
    lef, rig = min(ver, key=vx), max(ver, key=vx)
    q = np.float32([_intersect(top, lef), _intersect(top, rig), _intersect(bot, rig), _intersect(bot, lef)]) / sc
    if cv2.contourArea(q) < MIN_AREA * w * h:
        return None, "too small"
    return q, "ok"


def rectify(img, q, pad_bgr):
    tw = (np.linalg.norm(q[1] - q[0]) + np.linalg.norm(q[2] - q[3])) / 2
    th = (np.linalg.norm(q[3] - q[0]) + np.linalg.norm(q[2] - q[1])) / 2
    x0, y0 = q[0]
    dst = np.float32([[x0, y0], [x0 + tw, y0], [x0 + tw, y0 + th], [x0, y0 + th]])
    H = cv2.getPerspectiveTransform(q, dst)
    h, w = img.shape[:2]
    c = cv2.perspectiveTransform(np.float32([[[0, 0]], [[w, 0]], [[w, h]], [[0, h]]]), H).reshape(4, 2)
    mn, mx = np.floor(c.min(0)), np.ceil(c.max(0))
    T = np.array([[1, 0, -mn[0]], [0, 1, -mn[1]], [0, 0, 1]], np.float64)
    size = (int(mx[0] - mn[0]), int(mx[1] - mn[1]))
    return cv2.warpPerspective(img, T @ H, size, flags=cv2.INTER_CUBIC, borderMode=cv2.BORDER_CONSTANT, borderValue=pad_bgr)


def lean(q):
    """Left and right side lean in degrees (positive = top leans right)."""
    f = lambda a, b: math.degrees(math.atan2(q[a][0] - q[b][0], q[b][1] - q[a][1]))
    return round(f(0, 3), 2), round(f(1, 2), 2)


def main(manifest, out_manifest, out_dir, out_log):
    rows = list(csv.DictReader(open(manifest, encoding="utf-8")))
    os.makedirs(os.path.join(HERE, out_dir), exist_ok=True)
    out_rows, log = [], []
    for r in rows:
        img = cv2.imread(os.path.join(HERE, r["image_file"]))
        q, why = detect(img)
        pad = tuple(int(v) for v in r["pad_rgb"].split(","))[::-1]
        res = rectify(img, q, pad) if q is not None else img
        name = os.path.join(out_dir, os.path.basename(r["image_file"]))
        cv2.imwrite(os.path.join(HERE, name), res, [cv2.IMWRITE_JPEG_QUALITY, 95])
        out_rows.append(dict(r, image_file=name))
        ll, rl = lean(q) if q is not None else ("", "")
        log.append(dict(image_file=name, page_id=r["page_id"], condition=r["condition"], status=why,
                        lean_left=ll, lean_right=rl, quad="" if q is None else json.dumps(np.round(q, 1).tolist())))
    for path, data in ((out_manifest, out_rows), (out_log, log)):
        with open(os.path.join(HERE, path), "w", newline="", encoding="utf-8") as f:
            wr = csv.DictWriter(f, fieldnames=list(data[0].keys())); wr.writeheader(); wr.writerows(data)
    ok = sum(x["status"] == "ok" for x in log)
    print(f"{ok}/{len(log)} quadrilaterals found", file=sys.stderr)


if __name__ == "__main__":
    main(*sys.argv[1:5])
