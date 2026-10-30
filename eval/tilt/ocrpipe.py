"""Python port of the KotenOCR "koten" mode pipeline (RTMDet -> PARSeq -> block XY-cut reading order),
plus the small-angle deskew.  Mirrors the Swift sources in KotenOCR/OCR/ (see README.md for the
list of known differences).

    OCREngine.processKoten:  Deskew -> RTMDetector.detect -> crop -> PARSEQRecognizer.recognize
                             -> ReadingOrderProcessor.process -> join with "\n"

Run only with `python -I` from the venv described in README.md (numpy, onnxruntime, pillow, opencv).
"""
from __future__ import annotations

import math
import os
from dataclasses import dataclass, field

import cv2
import numpy as np
import onnxruntime as ort
from PIL import Image

# --------------------------------------------------------------------------------------
# Config values taken from KotenOCR/Models/ndl.yaml (score 0.3, nms 0.4 [unused], max 100)
SCORE_THRESHOLD = 0.3
MAX_DETECTIONS = 100
DET_SIZE = 1024          # RTMDetector.inputWidth/Height (the model file name says 1280, the model takes 1024)
REC_W, REC_H = 384, 32   # PARSEQRecognizer defaults used by koten mode


@dataclass
class Det:
    box: list            # [x1, y1, x2, y2] ints in image pixels
    score: float
    text: str = ""


# --------------------------------------------------------------------------------------
# Deskew (port of Deskew.swift)
DESKEW_MAX_ANGLE = 10.0
DESKEW_MIN_ANGLE = 0.3
DESKEW_MIN_GAIN = 1.01
DESKEW_MIN_INK = 200
DESKEW_WORK_LONG = 1000
DESKEW_MAX_POINTS = 80_000


def _downscale(img: Image.Image) -> np.ndarray:
    w0, h0 = img.size
    scale = min(1.0, DESKEW_WORK_LONG / max(w0, h0))
    w = max(1, int(round(w0 * scale)))
    h = max(1, int(round(h0 * scale)))
    a = np.asarray(img.convert("RGB"))
    if (w, h) != (w0, h0):
        a = cv2.resize(a, (w, h), interpolation=cv2.INTER_AREA)
    return a


def estimate_skew(img: Image.Image, orientation: str = "vertical"):
    """Return dict(angle, gain, ink, paper) like Deskew.estimateSkew (vertical text only here)."""
    px = _downscale(img)
    h, w = px.shape[:2]
    g = ((px[..., 0].astype(np.uint32) * 299 + px[..., 1].astype(np.uint32) * 587
          + px[..., 2].astype(np.uint32) * 114) // 1000).astype(np.int64)
    radius = max(7, max(w, h) // 40)
    margin = max(2, int(0.015 * max(w, h)))
    ii = np.zeros((h + 1, w + 1), dtype=np.int64)
    ii[1:, 1:] = g.cumsum(0).cumsum(1)
    ys = np.arange(h)
    xs = np.arange(w)
    y0 = np.clip(ys - radius, 0, h)
    y1 = np.clip(ys + radius + 1, 0, h)
    x0 = np.clip(xs - radius, 0, w)
    x1 = np.clip(xs + radius + 1, 0, w)
    S = ii[y1][:, x1] - ii[y0][:, x1] - ii[y1][:, x0] + ii[y0][:, x0]
    area = ((y1 - y0)[:, None] * (x1 - x0)[None, :]).astype(np.int64)
    ink = g * area * 100 < S * 85 - 400 * area
    Y, X = np.mgrid[0:h, 0:w]
    in_margin = (Y >= margin) & (Y < h - margin) & (X >= margin) & (X < w - margin)
    sel = ink & in_margin
    paper_sel = (~ink) & (Y > h // 5) & (Y < h * 4 // 5) & (g * area >= S) & (X > w // 5) & (X < w * 4 // 5)
    if paper_sel.any():
        paper = tuple(float(px[..., c][paper_sel].mean()) / 255.0 for c in range(3))
    else:
        paper = (1.0, 1.0, 1.0)
    yy, xx = np.nonzero(sel)
    n = len(xx)
    if n > DESKEW_MAX_POINTS:
        step = n / DESKEW_MAX_POINTS
        idx = np.arange(0, n, step).astype(int)
        idx = idx[idx < n]
        xx, yy = xx[idx], yy[idx]
        n = len(xx)
    if n < DESKEW_MIN_INK:
        return dict(angle=0.0, gain=1.0, ink=n, paper=paper)
    fx = xx.astype(np.float32) - np.float32(w) / 2
    fy = yy.astype(np.float32) - np.float32(h) / 2
    bins = int(math.sqrt(w * w + h * h)) + 2

    def score(deg: float) -> float:
        t = deg * math.pi / 180
        c, s = np.float32(math.cos(t)), np.float32(math.sin(t))
        u = fx * c - fy * s            # vertical lines: constant along a line tilted by +deg
        k = np.clip(np.floor(u + np.float32(bins // 2)).astype(np.int64), 0, bins - 1)
        hist = np.bincount(k, minlength=bins).astype(np.float64)
        return float((hist * hist).sum())

    best, best_angle = -1.0, 0.0
    for k in range(-20, 21):
        d = k * 0.5
        sc = score(d)
        if sc > best:
            best, best_angle = sc, d
    coarse = best_angle
    for k in range(-5, 6):
        if k == 0:
            continue
        d = coarse + k * 0.1
        sc = score(d)
        if sc > best:
            best, best_angle = sc, d
    zero = score(0.0)
    gain = best / zero if zero > 0 else 1.0
    return dict(angle=round(best_angle * 10) / 10, gain=gain, ink=n, paper=paper)


def deskew(img: Image.Image):
    """Return (image, angle).  Positive angle = page content was rotated CCW (see Deskew.swift)."""
    est = estimate_skew(img)
    should = (abs(est["angle"]) >= DESKEW_MIN_ANGLE and est["gain"] >= DESKEW_MIN_GAIN
              and est["ink"] >= DESKEW_MIN_INK)
    if not should:
        return img, 0.0
    fill = tuple(int(round(c * 255)) for c in est["paper"])
    # Deskew.swift: rotate(image, byDegrees: -angle) with positive = counter-clockwise.
    # PIL.rotate(angle) is counter-clockwise for positive angles as well, and expand=True grows the canvas.
    out = img.convert("RGB").rotate(-est["angle"], resample=Image.BICUBIC, expand=True, fillcolor=fill)
    return out, est["angle"]


# --------------------------------------------------------------------------------------
# Detector (port of RTMDetector.swift)
class Detector:
    def __init__(self, path: str, sess_opts=None):
        self.sess = ort.InferenceSession(path, sess_options=sess_opts, providers=["CPUExecutionProvider"])
        self.inp = self.sess.get_inputs()[0].name

    def detect(self, img: Image.Image):
        rgb = np.asarray(img.convert("RGB"))
        oh, ow = rgb.shape[:2]
        max_wh = max(ow, oh)
        dw = ow * DET_SIZE / max_wh
        dh = oh * DET_SIZE / max_wh
        canvas = np.zeros((DET_SIZE, DET_SIZE, 3), dtype=np.uint8)   # black pad, image at the top-left
        rw, rh = max(1, int(round(dw))), max(1, int(round(dh)))
        interp = cv2.INTER_AREA if max_wh > DET_SIZE else cv2.INTER_CUBIC
        canvas[:rh, :rw] = cv2.resize(rgb, (rw, rh), interpolation=interp)
        mean = np.array([123.675, 116.28, 103.53], dtype=np.float32)
        std = np.array([58.395, 57.12, 57.375], dtype=np.float32)
        t = ((canvas.astype(np.float32) - mean) / std).transpose(2, 0, 1)[None]
        dets, labels = self.sess.run(["dets", "labels"], {self.inp: np.ascontiguousarray(t)})
        dets = dets[0]
        out = []
        for i in range(dets.shape[0]):
            score = float(dets[i, 4])
            if score < SCORE_THRESHOLD:
                continue
            x1, y1, x2, y2 = (float(dets[i, k]) / DET_SIZE * max_wh for k in range(4))
            pad = (y2 - y1) * 0.02
            y1a, y2a = y1 - pad, y2 + pad
            box = [max(0, int(_rnd(x1))), max(0, int(_rnd(y1a))),
                   min(ow, int(_rnd(x2))), min(oh, int(_rnd(y2a)))]
            out.append(Det(box=box, score=score))
        out.sort(key=lambda d: -d.score)
        return out[:MAX_DETECTIONS]


def _rnd(v: float) -> float:
    """Swift .rounded(): half away from zero."""
    return math.floor(v + 0.5) if v >= 0 else -math.floor(-v + 0.5)


# --------------------------------------------------------------------------------------
# Recogniser (port of PARSEQRecognizer.swift)
def load_charset(yaml_path: str):
    content = open(yaml_path, encoding="utf-8").read()
    i = content.index("charset_train:")
    rest = content[i + len("charset_train:"):]
    q = rest.index('"')
    out, esc = [], False
    for ch in rest[q + 1:]:
        if esc:
            out.append({'"': '"', "\\": "\\", "n": "\n", "t": "\t"}.get(ch, ch))
            esc = False
        elif ch == "\\":
            esc = True
        elif ch == '"':
            break
        else:
            out.append(ch)
    return out


class Recognizer:
    def __init__(self, model_path: str, charset_path: str, sess_opts=None):
        self.sess = ort.InferenceSession(model_path, sess_options=sess_opts, providers=["CPUExecutionProvider"])
        self.inp = self.sess.get_inputs()[0].name
        self.out = self.sess.get_outputs()[0].name
        self.chars = load_charset(charset_path)

    def recognize(self, crop_rgb: np.ndarray) -> str:
        a = crop_rgb
        h, w = a.shape[:2]
        if h > w:
            a = np.rot90(a, k=1)      # 90 deg CCW, same pixel mapping as rotatePixels90CCW
        h, w = a.shape[:2]
        interp = cv2.INTER_AREA if (w > REC_W or h > REC_H) else cv2.INTER_CUBIC
        r = cv2.resize(np.ascontiguousarray(a), (REC_W, REC_H), interpolation=interp)
        t = (r.astype(np.float32) / 127.5 - 1.0).transpose(2, 0, 1)[None]
        logits = self.sess.run([self.out], {self.inp: np.ascontiguousarray(t)})[0][0]  # [seq, vocab]
        idx = logits.argmax(-1)
        s = []
        for k in idx:
            if k == 0:
                break
            if 0 <= k - 1 < len(self.chars):
                s.append(self.chars[k - 1])
        return "".join(s)


# --------------------------------------------------------------------------------------
# Reading order (port of ReadingOrder.swift, NDL block_xy_cut)
class _Node:
    def __init__(self, x0, y0, x1, y1):
        self.x0, self.y0, self.x1, self.y1 = x0, y0, x1, y1
        self.children = []
        self.line_idx = []
        self.num_lines = 0
        self.num_vertical = 0

    def is_x_split(self):
        return all(self.y0 == c.y0 and self.y1 == c.y1 for c in self.children)

    def is_vertical(self):
        return self.num_lines < self.num_vertical * 2


def _calc_min_span(hist):
    if len(hist) <= 1:
        return 0, max(1, len(hist)), 0.0
    mn, mx = int(hist.min()), int(hist.max())
    runs, in_run, start = [], False, 0
    for i, v in enumerate(hist):
        if v == mn:
            if not in_run:
                start, in_run = i, True
        elif in_run:
            runs.append((start, i))
            in_run = False
    if in_run:
        runs.append((start, len(hist)))
    if not runs:
        return 0, len(hist), 0.0
    best = runs[0]
    for r in runs[1:]:                         # Swift max(by:) returns the last maximal element for ties
        if (r[1] - r[0]) >= (best[1] - best[0]):
            best = r
    val = -float(mn) / float(mx) if mx > 0 else 0.0
    return best[0], best[1], np.float32(val)


def _iou(a, b):
    ix0, iy0, ix1, iy1 = max(a[0], b[0]), max(a[1], b[1]), min(a[2], b[2]), min(a[3], b[3])
    inter = float(max(0, ix1 - ix0)) * float(max(0, iy1 - iy0))
    if inter == 0:
        return 0.0
    ua = float((a[2] - a[0]) * (a[3] - a[1])) + float((b[2] - b[0]) * (b[3] - b[1])) - inter
    return inter / ua if ua > 0 else 0.0


def reading_order(dets, image_w, image_h):
    """Reorder detections like ReadingOrderProcessor.process."""
    if not dets:
        return []
    n = len(dets)
    boxes = [[np.float32(v) for v in d.box] for d in dets]
    grid = int(100.0 * math.sqrt(n))
    for b in boxes:
        if b[0] > b[2]:
            b[2] = b[0]
        if b[1] > b[3]:
            b[3] = b[1]
    x_min = min(b[0] for b in boxes)
    y_min = min(b[1] for b in boxes)
    x_max = max(b[2] for b in boxes)
    y_max = max(b[3] for b in boxes)
    wp, hp = np.float32(x_max - x_min), np.float32(y_max - y_min)
    if wp > 0 and hp > 0:
        xg = np.float32(grid) if wp < hp else np.float32(grid) * (wp / hp)
        yg = np.float32(grid) if hp < wp else np.float32(grid) * (hp / wp)
        for b in boxes:
            b[0] = max(np.float32(0), np.floor((b[0] - x_min) * xg / wp))
            b[1] = max(np.float32(0), np.floor((b[1] - y_min) * yg / hp))
            b[2] = max(np.float32(0), np.floor((b[2] - x_min) * xg / wp))
            b[3] = max(np.float32(0), np.floor((b[3] - y_min) * yg / hp))
    ib = [[max(0, int(v)) for v in b] for b in boxes]

    xg_n = max(b[2] for b in ib) + 1
    yg_n = max(b[3] for b in ib) + 1
    table = np.zeros((yg_n, xg_n), dtype=np.int32)
    for b in ib:
        table[b[1]:min(b[3], yg_n), b[0]:min(b[2], xg_n)] = 1
    root = _Node(0, 0, table.shape[1], table.shape[0])
    _xy_cut(table, root)
    leaves = []
    _collect(root, leaves)
    for i, b in enumerate(ib):
        best_j, best_iou = 0, -float("inf")
        for j, lf in enumerate(leaves):
            v = _iou(b, [lf.x0, lf.y0, lf.x1, lf.y1])
            if v > best_iou:
                best_iou, best_j = v, j
        leaves[best_j].line_idx.append(i)
    _sort_nodes(root, ib)
    ranks = [-1] * n
    _ranking(root, ranks, 0)
    mx = max(ranks)
    for i in range(n):
        if ranks[i] < 0:
            mx += 1
            ranks[i] = mx
    order = sorted(range(n), key=lambda i: ranks[i])
    return [dets[i] for i in order]


def _xy_cut(table, node):
    x0, y0, x1, y1 = node.x0, node.y0, node.x1, node.y1
    if not (x1 > x0 and y1 > y0):
        return
    sub = table[y0:y1, x0:x1]
    xh = sub.sum(0)
    yh = sub.sum(1)
    xb, xe, xv = _calc_min_span(xh)
    yb, ye, yv = _calc_min_span(yh)
    xb += x0; xe += x0; yb += y0; ye += y0
    if (x0, x1, y0, y1) == (xb, xe, yb, ye):
        return
    if yv < xv:
        _split(node, table, "x", xb, xe)
    elif xv < yv:
        _split(node, table, "y", yb, ye)
    elif (xe - xb) < (ye - yb):
        _split(node, table, "y", yb, ye)
    else:
        _split(node, table, "x", xb, xe)


def _split(parent, table, axis, beg, end):
    if axis == "x":
        specs = [(None, None, beg, None), (beg, None, end, None), (end, None, None, None)]
    else:
        specs = [(None, None, None, beg), (None, beg, None, end), (None, end, None, None)]
    for x0, y0, x1, y1 in specs:
        cx0 = parent.x0 if x0 is None else x0
        cy0 = parent.y0 if y0 is None else y0
        cx1 = parent.x1 if x1 is None else x1
        cy1 = parent.y1 if y1 is None else y1
        if not (cx0 < cx1 and cy0 < cy1):
            continue
        if (cx0, cy0, cx1, cy1) == (parent.x0, parent.y0, parent.x1, parent.y1):
            continue
        child = _Node(cx0, cy0, cx1, cy1)
        parent.children.append(child)
        _xy_cut(table, child)


def _collect(node, leaves):
    if not node.children:
        leaves.append(node)
    else:
        for c in node.children:
            _collect(c, leaves)


def _sort_nodes(node, boxes):
    if node.line_idx:
        nv = sum(1 for i in node.line_idx if (boxes[i][2] - boxes[i][0]) < (boxes[i][3] - boxes[i][1]))
        node.num_lines = len(node.line_idx)
        node.num_vertical = nv
        if node.num_lines > 1:
            if node.is_vertical():
                node.line_idx.sort(key=lambda i: (-boxes[i][0], boxes[i][1]))
            else:
                node.line_idx.sort(key=lambda i: (boxes[i][1], boxes[i][0]))
    else:
        for c in node.children:
            a, b = _sort_nodes(c, boxes)
            node.num_lines += a
            node.num_vertical += b
        if node.is_x_split() and node.is_vertical():
            node.children.reverse()
    return node.num_lines, node.num_vertical


def _ranking(node, ranks, rank):
    for i in node.line_idx:
        ranks[i] = rank
        rank += 1
    for c in node.children:
        rank = _ranking(c, ranks, rank)
    return rank


# --------------------------------------------------------------------------------------
@dataclass
class Result:
    dets: list                      # in reading order
    text: str                       # lines joined with "\n"
    raw_dets: list = field(default_factory=list)   # detection order (by score), before reading order
    deskew_angle: float = 0.0
    image_size: tuple = (0, 0)


class Pipeline:
    def __init__(self, models_dir: str, deskew_on: bool = False, per_line=None, threads: int = 0):
        so = ort.SessionOptions()
        if threads:
            so.intra_op_num_threads = threads
        self.det = Detector(os.path.join(models_dir, "rtmdet-s-1280x1280.onnx"), so)
        self.rec = Recognizer(os.path.join(models_dir, "parseq-ndl-32x384-tiny-10.onnx"),
                              os.path.join(models_dir, "NDLmoji.yaml"), so)
        self.deskew_on = deskew_on
        self.per_line = per_line        # callable(crop_rgb ndarray, box, page PIL image) -> ndarray, or None

    def run(self, img: Image.Image) -> Result:
        img = img.convert("RGB")
        angle = 0.0
        if self.deskew_on:
            img, angle = deskew(img)
        dets = self.det.detect(img)
        rgb = np.asarray(img)
        H, W = rgb.shape[:2]
        for d in dets:
            x1, y1, x2, y2 = d.box
            # CGImage.cropping(to: CGRect(x: max(0,x1), y: max(0,y1), w: max(1,x2-x1), h: max(1,y2-y1)))
            cx0, cy0 = max(0, x1), max(0, y1)
            cx1, cy1 = min(W, cx0 + max(1, x2 - x1)), min(H, cy0 + max(1, y2 - y1))
            if cx1 <= cx0 or cy1 <= cy0:
                continue
            crop = rgb[cy0:cy1, cx0:cx1]
            if self.per_line is not None:
                crop = self.per_line(crop, d.box, img)
            d.text = self.rec.recognize(crop)
        raw = list(dets)
        ordered = reading_order(dets, W, H)
        return Result(dets=ordered, text="\n".join(d.text for d in ordered), raw_dets=raw,
                      deskew_angle=angle, image_size=(W, H))
