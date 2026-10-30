"""Adapter that wires the per-line tilt prototype (branch `line-tilt`) into measure.py.

    python -I measure.py --per-line on --per-line-module perline_linetilt_adapter.py ...

The prototype is a Python mirror written next to the Swift work (functions `estimate_lean`, `plan_line`,
`oriented_crop`).  A copy is kept next to this file as `linetilt_proto_ocr.py` (provenance in its header); set
LINETILT_PROTO=/path/to/ocr.py to use another version.

Only the oriented-crop step is used.  The prototype's own garbage filter, de-duplication and simplified reading order
(`run_page(..., dedupe=, drop_garbage=)`) are NOT applied, so that --per-line differs from the baseline in the crop
only and the app's reading order is kept.
"""
import importlib.util
import os

import numpy as np

_path = os.environ.get("LINETILT_PROTO") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "linetilt_proto_ocr.py")
if not _path or not os.path.exists(_path):
    raise SystemExit(f"line-tilt prototype not found: {_path} (set LINETILT_PROTO)")
_spec = importlib.util.spec_from_file_location("linetilt_proto_ocr", _path)
_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_mod)

_cache = {}


def rectify_line(crop_rgb, box, page):
    if _cache.get("page") is not page:     # keep a reference so a recycled id() cannot return a stale array
        rgb = np.asarray(page.convert("RGB"))
        _cache.update(page=page, rgb=rgb, gray=_mod.gray_of(rgb))
    H, W = _cache["rgb"].shape[:2]
    x1, y1, x2, y2 = max(0, box[0]), max(0, box[1]), min(W, box[2]), min(H, box[3])
    out, _info = _mod.plan_line(_cache["rgb"], _cache["gray"], [x1, y1, x2, y2])
    return out if out.size else crop_rgb
