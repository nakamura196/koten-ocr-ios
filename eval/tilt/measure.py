"""Step 3: run the KotenOCR (koten mode) pipeline on every variant and score it.

    python -I measure.py --deskew off --per-line off --out results/baseline.csv
    python -I measure.py --deskew on  --per-line off --out results/deskew.csv
    python -I summarize.py results/baseline.csv results/deskew.csv

Metrics (all on normalised text, see normalise()):
  cer          Levenshtein(hyp, ref) / len(ref)   page level; hyp = lines in the app's reading order joined
  bag_cer      reading-order-independent: (max(|ref|,|hyp|) - multiset overlap) / |ref|
  leak3/leak5  number of recognised lines containing an n-gram (n=3 / 5) that occurs in a neighbouring reference line
               (assigned line +/- 1) but not in the reference line the recognised line was assigned to
  dup_within   immediate repeats inside one recognised line: a unit of >=3 chars repeated back-to-back
  dup_cross    recognised lines (not the first) sharing a 5-gram that occurs in more recognised lines than in the reference
"""
import argparse
import csv
import importlib.util
import json
import os
import re
import sys
import time
import unicodedata
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)          # python -I does not put the script dir on sys.path

from PIL import Image, ImageOps  # noqa: E402

DEFAULT_MODELS = os.path.expanduser("~/git/hi/miyako/koten-ocr-ios/KotenOCR/Models")
DEFAULT_PERLINE = os.path.expanduser("~/git/hi/miyako/koten-ocr-ios.worktrees/line-tilt")


# ------------------------------------------------------------------ text metrics
def normalise(s: str) -> str:
    """NFKC, then drop whitespace/control characters and punctuation/symbol marks (Unicode categories Z*, C*, P*, S*).
    Line breaks therefore do not matter.  No old/new-form or variant-kana folding is applied (see README)."""
    s = unicodedata.normalize("NFKC", s)
    return "".join(ch for ch in s if unicodedata.category(ch)[0] not in "ZCPS")


def levenshtein(a: str, b: str) -> int:
    if not a:
        return len(b)
    if not b:
        return len(a)
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        cur = [i]
        for j, cb in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ca != cb)))
        prev = cur
    return prev[-1]


def grams(s: str, n: int):
    return {s[i:i + n] for i in range(len(s) - n + 1)}


def leak_count(rec_lines, ref_lines, n):
    cnt = 0
    ref_g = [grams(r, n) for r in ref_lines]
    ref_g3 = [grams(r, 3) for r in ref_lines]
    for r in rec_lines:
        if len(r) < n or not ref_lines:
            continue
        rg = grams(r, n)
        # assign to the reference line sharing most trigrams (ties: first)
        r3 = grams(r, 3)
        scores = [len(r3 & g) for g in ref_g3]
        a = max(range(len(ref_lines)), key=lambda k: scores[k])
        if scores[a] == 0:
            continue
        neigh = [k for k in (a - 1, a + 1) if 0 <= k < len(ref_lines)]
        if any((rg & ref_g[k]) - ref_g[a] for k in neigh):
            cnt += 1
    return cnt


def dup_counts(rec_lines, ref_lines):
    within = sum(len(list(re.finditer(r"(.{3,}?)\1", r))) for r in rec_lines)
    n = 5
    rec_cnt, first = defaultdict(list), {}
    for i, r in enumerate(rec_lines):
        for g in grams(r, n):
            rec_cnt[g].append(i)
    ref_cnt = Counter()
    for r in ref_lines:
        for g in grams(r, n):
            ref_cnt[g] += 1
    flagged = set()
    for g, idx in rec_cnt.items():
        if len(idx) >= 2 and len(idx) > ref_cnt.get(g, 0):
            flagged.update(idx[1:])
    return within, len(flagged)


def score(hyp_lines_raw, ref_lines_raw):
    hyp_lines = [normalise(t) for t in hyp_lines_raw]
    ref_lines = [normalise(t) for t in ref_lines_raw]
    hyp_lines = [t for t in hyp_lines if t]
    ref_lines = [t for t in ref_lines if t]
    ref, hyp = "".join(ref_lines), "".join(hyp_lines)
    d = levenshtein(hyp, ref)
    over = sum((Counter(hyp) & Counter(ref)).values())
    within, cross = dup_counts(hyp_lines, ref_lines)
    return dict(n_ref=len(ref), n_hyp=len(hyp), edit=d, cer=d / len(ref), bag_cer=(max(len(ref), len(hyp)) - over) / len(ref),
                leak3=leak_count(hyp_lines, ref_lines, 3), leak5=leak_count(hyp_lines, ref_lines, 5),
                dup_within=within, dup_cross=cross)


# ------------------------------------------------------------------ per-line hook
def load_per_line(arg_module, root):
    """Hook for the per-line tilt correction being developed on branch `line-tilt`.

    Contract: a Python file exposing   rectify_line(crop_rgb: np.ndarray[h,w,3 uint8], box: [x1,y1,x2,y2],
    page: PIL.Image) -> np.ndarray   which returns the (possibly de-rotated) line crop that is fed to PARSeq.
    Pass its path with --per-line-module, or set KOTEN_PERLINE_MODULE.  Nothing is imported when --per-line off.
    """
    path = arg_module or os.environ.get("KOTEN_PERLINE_MODULE")
    if not path:
        sys.exit("--per-line on needs --per-line-module <file.py> (or KOTEN_PERLINE_MODULE). "
                 f"As of writing, branch line-tilt ({root}) contains no Python prototype; see README 'Per-line hook'.")
    spec = importlib.util.spec_from_file_location("perline_proto", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.rectify_line


# ------------------------------------------------------------------ main
_PIPE = None


def _init(models, deskew_on, per_line_path, threads, strip_gate=True):
    global _PIPE
    import ocrpipe
    pl = load_per_line(per_line_path, DEFAULT_PERLINE) if per_line_path else None
    _PIPE = ocrpipe.Pipeline(models, deskew_on=deskew_on, per_line=pl, threads=threads, strip_gate=strip_gate)


def _work(job):
    row, refpath = job
    ref = json.load(open(refpath, encoding="utf-8"))
    t = time.time()
    res = _PIPE.run(ImageOps.exif_transpose(Image.open(os.path.join(HERE, row["image_file"]))))  # upright, as the phone shows it
    dt = time.time() - t
    ref_lines = [l["text"] for l in ref["lines"]]
    m = score([d.text for d in res.dets], ref_lines)
    # leak / dup are defined on the recognised lines; reading order does not change the set of lines,
    # so cer/bag_cer use the app's reading order and the line-level counts use the same list.
    out = dict(image_file=row["image_file"], page_id=row["page_id"], book_id=row["book_id"], condition=row["condition"],
               family=row["family"], n_det=len(res.dets), n_ref_lines=len([l for l in ref_lines if normalise(l)]),
               deskew_angle=res.deskew_angle, secs=round(dt, 2), **m)
    return out, dict(image_file=row["image_file"], lines=[dict(box=d.box, score=round(d.score, 4), text=d.text) for d in res.dets])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--deskew", choices=["on", "off"], default="off")
    ap.add_argument("--strip-gate", choices=["on", "off"], default="on", help="deskew: decline when left/middle/right strip angles disagree")
    ap.add_argument("--per-line", choices=["on", "off"], default="off")
    ap.add_argument("--per-line-module", default=None)
    ap.add_argument("--models", default=DEFAULT_MODELS)
    ap.add_argument("--manifest", default=os.path.join(HERE, "manifest.csv"))
    ap.add_argument("--out", required=True)
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--limit", type=int, default=0, help="only the first N manifest rows (smoke test)")
    ap.add_argument("--only", default="", help="comma list of condition names to run")
    a = ap.parse_args()

    rows = list(csv.DictReader(open(a.manifest, encoding="utf-8")))
    if a.only:
        keep = set(a.only.split(","))
        rows = [r for r in rows if r["condition"] in keep]
    if a.limit:
        rows = rows[:a.limit]
    jobs = [(r, os.path.join(HERE, "data", "pages", r["page_id"] + ".json")) for r in rows]
    per_line_path = (a.per_line_module or os.environ.get("KOTEN_PERLINE_MODULE") or "MISSING") if a.per_line == "on" else None
    if per_line_path == "MISSING":
        load_per_line(None, DEFAULT_PERLINE)       # exits with an explanatory message
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    results, hyps = [], []
    t0 = time.time()
    initargs = (a.models, a.deskew == "on", per_line_path, 1 if a.workers > 1 else 0, a.strip_gate == "on")
    if a.workers > 1:
        import multiprocessing as mp
        with mp.get_context("spawn").Pool(a.workers, initializer=_init, initargs=initargs) as pool:
            for k, (r, h) in enumerate(pool.imap(_work, jobs, chunksize=2), 1):
                results.append(r); hyps.append(h)
                if k % 50 == 0:
                    print(f"{k}/{len(jobs)} {time.time() - t0:.0f}s", file=sys.stderr, flush=True)
    else:
        _init(*initargs)
        for k, j in enumerate(jobs, 1):
            r, h = _work(j)
            results.append(r); hyps.append(h)
    with open(a.out, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(results[0].keys()))
        w.writeheader()
        w.writerows(results)
    with open(os.path.splitext(a.out)[0] + ".hyp.jsonl", "w", encoding="utf-8") as f:
        for h in hyps:
            f.write(json.dumps(h, ensure_ascii=False) + "\n")
    print(f"wrote {len(results)} rows to {a.out} in {time.time() - t0:.0f}s", file=sys.stderr)


if __name__ == "__main__":
    main()
