# Provenance: verbatim copy of the Python prototype for branch `line-tilt` (Swift: KotenOCR/OCR/LineTilt.swift,
# commit 5fb5452), taken from the line-tilt agent's scratch directory on 2026-10-29 (ocr.py, 298 lines).
# Only change from the original: MODELS is read from $KOTEN_MODELS (default: main checkout) instead of the
# hard-coded line-tilt worktree path.  eval/tilt/perline_linetilt_adapter.py imports plan_line() from this file.
"""Python mirror of the KotenOCR Koten pipeline (RTMDet + PARSeq), plus the line-tilt prototype."""
import math, os
import numpy as np
import cv2
import onnxruntime as ort

MODELS = os.environ.get("KOTEN_MODELS", os.path.expanduser("~/git/hi/miyako/koten-ocr-ios/KotenOCR/Models"))


def load_charset():
    t = open(MODELS + "/NDLmoji.yaml", encoding="utf-8").read()
    s = t[t.index("charset_train:"):].split('"', 1)[1]
    out, esc = [], False
    for ch in s:
        if esc:
            out.append({'"': '"', "\\": "\\", "n": "\n", "t": "\t"}.get(ch, ch)); esc = False
        elif ch == "\\":
            esc = True
        elif ch == '"':
            break
        else:
            out.append(ch)
    return out


_det = _rec = _cs = None


def sessions():
    global _det, _rec, _cs
    if _det is None:
        so = ort.SessionOptions(); so.intra_op_num_threads = 4
        _det = ort.InferenceSession(MODELS + "/rtmdet-s-1280x1280.onnx", so)
        _rec = ort.InferenceSession(MODELS + "/parseq-ndl-32x384-tiny-10.onnx", so)
        _cs = load_charset()
    return _det, _rec, _cs


def detect(rgb, thr=0.3):
    det, _, _ = sessions()
    H, W = rgb.shape[:2]
    mx = max(W, H)
    dw, dh = round(W * 1024 / mx), round(H * 1024 / mx)
    canvas = np.zeros((1024, 1024, 3), np.float32)
    canvas[:dh, :dw] = cv2.resize(rgb, (dw, dh), interpolation=cv2.INTER_AREA)
    mean = np.array([123.675, 116.28, 103.53], np.float32); std = np.array([58.395, 57.12, 57.375], np.float32)
    x = ((canvas - mean) / std).transpose(2, 0, 1)[None]
    dets, labels = det.run(["dets", "labels"], {"input": x})
    out = []
    for d in dets[0]:
        if d[4] < thr:
            continue
        x1, y1, x2, y2 = [v / 1024 * mx for v in d[:4]]
        pad = (y2 - y1) * 0.02
        out.append(dict(box=[max(0, round(x1)), max(0, round(y1 - pad)), min(W, round(x2)), min(H, round(y2 + pad))],
                        score=float(d[4])))
    out.sort(key=lambda d: -d["score"])
    return out[:100]


def recognize(crop):
    _, rec, cs = sessions()
    if crop.shape[0] > crop.shape[1]:
        crop = np.rot90(crop, 1)  # CCW
    r = cv2.resize(np.ascontiguousarray(crop), (384, 32), interpolation=cv2.INTER_AREA if crop.shape[1] > 384 else cv2.INTER_CUBIC)
    x = (r.astype(np.float32) / 127.5 - 1.0).transpose(2, 0, 1)[None]
    y = rec.run(None, {"images": x})[0][0]
    res = []
    for t in y.argmax(-1):
        if t == 0:
            break
        if t - 1 < len(cs):
            res.append(cs[t - 1])
    return "".join(res)


# ---------------------------------------------------------------- line tilt

def gray_of(rgb):
    return (0.299 * rgb[..., 0] + 0.587 * rgb[..., 1] + 0.114 * rgb[..., 2]).astype(np.float32)


def ink_of(g):
    """Ink = clearly darker than the region's paper level (median of the brighter half)."""
    paper = np.percentile(g, 75)
    return g < paper * 0.78


ANGLES = np.arange(-6.0, 6.001, 0.25)


def estimate_lean(g, box, min_aspect=3.0):
    """Lean (degrees, x = x0 + y*tan) of the vertical line inside `box`, from the sharpest
    projection profile of the ink inside the box. Returns dict or None."""
    x1, y1, x2, y2 = box
    w, h = x2 - x1, y2 - y1
    if h < min_aspect * w or h < 48 or w < 6:
        return None
    reg = g[y1:y2, x1:x2]
    # downscale long boxes so the work is bounded (~256 rows)
    s = min(1.0, 256.0 / h)
    if s < 1.0:
        reg = cv2.resize(reg, (max(4, round(w * s)), round(h * s)), interpolation=cv2.INTER_AREA)
    m = ink_of(reg)
    ys, xs = np.nonzero(m)
    if len(xs) < 30:
        return None
    rh, rw = reg.shape
    yc = ys - rh / 2.0
    nb = rw + 2 * int(rh * math.tan(math.radians(6.5))) + 4
    off = nb / 2.0
    best = None; s0 = None
    for a in ANGLES:
        u = np.floor(xs - rw / 2.0 - yc * math.tan(math.radians(a)) + off).astype(int)
        hist = np.bincount(u, minlength=nb).astype(np.float64)
        sc = float((hist * hist).sum())
        if abs(a) < 1e-9:
            s0 = sc
        if best is None or sc > best[1]:
            best = (a, sc, hist)
    a, sc, hist = best
    # parabolic refinement
    return dict(angle=float(a), gain=sc / s0, hist=hist, off=off, scale=s, rw=rw, rh=rh)


def ink_extent(est, w):
    """Width (in original px) of the main ink lobe around the box centre, along the line's normal."""
    hist = est["hist"]; s = est["scale"]; off = est["off"]
    k = np.ones(3) / 3
    p = np.convolve(hist, k, mode="same")
    c = int(round(off))  # box centre in u-coordinates
    win = max(2, int(est["rw"] * 0.3))
    lo, hi = max(0, c - win), min(len(p), c + win + 1)
    pk = lo + int(np.argmax(p[lo:hi]))
    thr = p[pk] * 0.12
    l = pk
    while l > 0 and p[l - 1] > thr:
        l -= 1
    r = pk
    while r < len(p) - 1 and p[r + 1] > thr:
        r += 1
    centre_u = ((l + r + 1) / 2.0 - off) / s  # offset from box centre, orig px (at mid-height)
    width = (r - l + 1) / s
    return centre_u, width


def oriented_crop(rgb, cx, cy, angle, w, h, fill=None):
    """Crop a w x h rectangle centred at (cx,cy) whose long axis leans by `angle` (x = x0 + y tan)."""
    t = math.radians(angle)
    c, s = math.cos(t), math.sin(t)
    W, H = int(round(w)), int(round(h))
    # dst (i,j) -> src: src = C + (i - W/2) * n + (j - H/2) * d ; d=(s,c), n=(c,-s)
    M = np.array([[c, s, cx - c * W / 2 - s * H / 2],
                  [-s, c, cy + s * W / 2 - c * H / 2]], np.float32)
    if fill is None:
        fill = tuple(int(v) for v in np.median(rgb.reshape(-1, 3)[::97], 0))
    return cv2.warpAffine(rgb, M, (W, H), flags=cv2.INTER_LINEAR | cv2.WARP_INVERSE_MAP,
                          borderMode=cv2.BORDER_CONSTANT, borderValue=fill)


MIN_LEAN = 0.5
MIN_GAIN = 1.03


def plan_line(rgb, g, box):
    """Return (crop, info) for one detection; info['tilted'] tells whether an oriented crop was used."""
    x1, y1, x2, y2 = box
    w, h = x2 - x1, y2 - y1
    est = estimate_lean(g, box)
    if est is None or abs(est["angle"]) < MIN_LEAN or est["gain"] < MIN_GAIN:
        return rgb[y1:y2, x1:x2], dict(tilted=False, angle=est["angle"] if est else None, gain=est["gain"] if est else None)
    a = est["angle"]
    cu, width = ink_extent(est, w)
    t = math.radians(a)
    expected = w - h * abs(math.tan(t))  # width of a line that exactly fits the box
    width = min(max(width, 0.6 * expected) * 1.12 + 4, w) * math.cos(t)
    cx = (x1 + x2) / 2.0 + cu
    cy = (y1 + y2) / 2.0
    hh = h / math.cos(t) - (w - width) * abs(math.tan(t)) * 0  # keep full height
    crop = oriented_crop(rgb, cx, cy, a, width, hh)
    return crop, dict(tilted=True, angle=a, gain=est["gain"], width=width, cx=cx, cy=cy, h=hh)


def is_garbage(text):
    return len(text) > 0 and all(ch in "□〓�■" for ch in text)


def run_page(rgb, tilt=False, dedupe=False, drop_garbage=False, dets=None):
    if dets is None:
        dets = detect(rgb)
    g = gray_of(rgb)
    lines = []
    for d in dets:
        box = d["box"]
        if tilt:
            crop, info = plan_line(rgb, g, box)
        else:
            x1, y1, x2, y2 = box
            crop, info = rgb[y1:y2, x1:x2], dict(tilted=False)
        if crop.size == 0:
            continue
        text = recognize(crop)
        if info.get("tilted") and sum(ch in "□〓�" for ch in text) >= 3:
            x1, y1, x2, y2 = box
            alt = recognize(rgb[y1:y2, x1:x2])
            if sum(ch in "□〓�" for ch in alt) < sum(ch in "□〓�" for ch in text):
                text = alt; info = dict(info, fallback=True)
        if drop_garbage and is_garbage(text):
            continue
        lines.append(dict(box=box, text=text, info=info))
    if dedupe:
        lines = drop_same_line_duplicates(lines)
    lines = reading_order(lines)
    return lines


def reading_order(lines):
    """Simple vertical-text order: right-to-left by box centre x (enough for single-block pages)."""
    return sorted(lines, key=lambda l: (-(l["box"][0] + l["box"][2]) / 2, l["box"][1]))


# ---------------------------------------------------------------- metrics

def lev(a, b):
    if not a: return len(b)
    if not b: return len(a)
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        cur = [i]
        for j, cb in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ca != cb)))
        prev = cur
    return prev[-1]


def cer(hyp, ref):
    return lev(hyp, ref) / max(1, len(ref))


def lcs_sub(a, b):
    best = 0
    dp = [0] * (len(b) + 1)
    for i in range(1, len(a) + 1):
        new = [0] * (len(b) + 1)
        for j in range(1, len(b) + 1):
            if a[i - 1] == b[j - 1]:
                new[j] = dp[j - 1] + 1
                best = max(best, new[j])
        dp = new
    return best


def neighbour_repeats(lines, k=3):
    """Adjacent lines (by x-order) that share a run of >=k identical characters (leaked text)."""
    n = 0; pairs = []
    for a, b in zip(lines, lines[1:]):
        if lcs_sub(a["text"], b["text"]) >= k:
            n += 1; pairs.append((a["text"], b["text"]))
    return n, pairs


# ---------------------------------------------------------------- same-line duplicates

def sub_similarity(small, large):
    """1 - (edit distance of `small` against its best-matching substring of `large`) / len(small)."""
    if not small:
        return 0.0
    prev = [0] * (len(large) + 1)  # free start anywhere in large
    for i, a in enumerate(small, 1):
        cur = [i]
        for j, b in enumerate(large, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a != b)))
        prev = cur
    return 1.0 - min(prev) / len(small)


def drop_same_line_duplicates(lines, min_overlap=0.6, min_sim=0.6):
    """Drop a line whose box lies mostly inside another line's box (x and y) and whose text is
    mostly a substring of that line's text: the detector found the same column twice."""
    keep = [True] * len(lines)
    def area(b): return (b[2] - b[0]) * (b[3] - b[1])
    order = sorted(range(len(lines)), key=lambda i: -area(lines[i]["box"]))
    for ii, i in enumerate(order):
        if not keep[i]:
            continue
        A = lines[i]["box"]
        for j in order[ii + 1:]:
            if not keep[j]:
                continue
            B = lines[j]["box"]
            ox = min(A[2], B[2]) - max(A[0], B[0]); oy = min(A[3], B[3]) - max(A[1], B[1])
            if ox <= 0 or oy <= 0:
                continue
            if ox < min_overlap * (B[2] - B[0]) or oy < min_overlap * (B[3] - B[1]):
                continue
            if sub_similarity(lines[j]["text"], lines[i]["text"]) >= min_sim:
                keep[j] = False
    return [l for l, k in zip(lines, keep) if k]
