"""Strip-consistency gate: compute the left/middle/right strip angles for every manifest image (no OCR) and, from the
existing baseline / old-gate deskew CSVs, derive CER at any threshold.

    python -I tune_gate.py results/baseline.csv results/deskew_oldgate.csv > results/gate_tuning.md

For a given threshold an image is either rotated (then its row equals the old-gate deskew row) or declined (then it
equals the baseline row), because the OCR pipeline is deterministic given the decision.  This is exact for the
decision rule, up to ONNX nondeterminism.
"""
import csv
import os
import sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from PIL import Image, ImageOps  # noqa: E402
import ocrpipe  # noqa: E402

OUT = os.path.join(HERE, "results", "strip_angles.csv")


def compute():
    rows = list(csv.DictReader(open(os.path.join(HERE, "manifest.csv"), encoding="utf-8")))
    out = []
    for r in rows:
        est = ocrpipe.estimate_skew(ImageOps.exif_transpose(Image.open(os.path.join(HERE, r["image_file"]))).convert("RGB"))
        s = ["" if a is None else a for a in est["strips"]]
        out.append(dict(image_file=r["image_file"], condition=r["condition"], angle=est["angle"], gain=round(est["gain"], 4),
                        ink=est["ink"], strip_l=s[0], strip_m=s[1], strip_r=s[2]))
    with open(OUT, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(out[0].keys()))
        w.writeheader(); w.writerows(out)


def main():
    if not os.path.exists(OUT):
        compute()
    base = {r["image_file"]: r for r in csv.DictReader(open(sys.argv[1], encoding="utf-8"))}
    old = {r["image_file"]: r for r in csv.DictReader(open(sys.argv[2], encoding="utf-8"))}
    sa = list(csv.DictReader(open(OUT, encoding="utf-8")))
    focus = ["rot+0.0", "rot+3.0", "rot+8.0", "rot-8.0", "key-up1", "key-up2", "key-up3", "key-down2", "key-down3", "curl4", "lightkey-up2", "lightkey-down2"]
    print("| spread / sign-noise (99=sign rule off) | all-rot CER% | all-key CER% | key3 CER% | key3 leak3 | rot3-8 CER% | rot3-8 leak3 | rot+0 CER% | declined rot(3..8) | declined key3 | declined total |")
    print("|---|---|---|---|---|---|---|---|---|---|---|")
    for thr, sn in [(t_, n_) for n_ in (0.5, 1.0, 99) for t_ in (1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.5)] + [(99, 99)]:
        agg = defaultdict(lambda: defaultdict(float))
        dec = defaultdict(int); tot = 0
        for r in sa:
            st = [float(x) if x != "" else None for x in (r["strip_l"], r["strip_m"], r["strip_r"])]
            ok = ocrpipe.strips_consistent(st, thr, sn) if thr < 99 else True
            src = (old if ok else base)[r["image_file"]]
            c = r["condition"]
            fam = "rot" if c.startswith("rot") else "key" if c.startswith("key") or c.startswith("lightkey") else "other"
            groups = [fam]
            if c in ("key-up3", "key-down3"): groups.append("key3")
            if c in ("rot-3.0", "rot+3.0", "rot-5.0", "rot+5.0", "rot-8.0", "rot+8.0"): groups.append("rot38")
            if c == "rot+0.0": groups.append("rot0")
            for g in groups:
                a = agg[g]; a["e"] += float(src["edit"]); a["n"] += float(src["n_ref"]); a["l"] += float(src["leak3"])
                if not ok: dec[g] += 1
            if not ok: tot += 1
        f = lambda g: 100 * agg[g]["e"] / agg[g]["n"]
        print(f"| {(str(thr)+' / '+str(sn)) if thr < 99 else 'gate off (old)'} | {f('rot'):.1f} | {f('key'):.1f} | {f('key3'):.1f} | {int(agg['key3']['l'])} | {f('rot38'):.1f} | {int(agg['rot38']['l'])} | {f('rot0'):.1f} | {dec['rot38']}/180 | {dec['key3']}/60 | {tot}/570 |")
    print()
    print("Mean strip angles (L / M / R) per condition")
    print("| condition | L | M | R | global |")
    print("|---|---|---|---|---|")
    by = defaultdict(list)
    for r in sa: by[r["condition"]].append(r)
    for c, rs in by.items():
        def mean(k):
            v = [float(r[k]) for r in rs if r[k] != ""]
            return sum(v) / len(v) if v else float("nan")
        print(f"| {c} | {mean('strip_l'):.2f} | {mean('strip_m'):.2f} | {mean('strip_r'):.2f} | {mean('angle'):.2f} |")


if __name__ == "__main__":
    main()
