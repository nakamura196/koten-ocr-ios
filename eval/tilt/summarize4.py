"""Four-configuration summary with a page-level bootstrap CI for the CER difference against the baseline.

    python -I summarize4.py results/baseline.csv results/deskew.csv results/perline.csv results/deskew_perline.csv

Order of the arguments = baseline first.  CER = micro average (sum edits / sum reference characters) per condition
(30 pages).  Difference = CER(config) - CER(baseline) in percentage points; 95 % CI from 10 000 bootstrap resamples
of the 30 pages (same pages in both configurations, paired), seed 20261029.  Leak = leak3 total.
Also written: results/summary4.md and results/summary4_ci.csv (numbers only: no images, no dataset text).
"""
import csv
import os
import random
import sys
from collections import OrderedDict, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
NAMES = ["baseline", "deskew", "perline", "deskew+perline"]
B = 10000


def load(path):
    d = defaultdict(dict)
    for r in csv.DictReader(open(path, encoding="utf-8")):
        d[r["condition"]][r["page_id"]] = (float(r["edit"]), float(r["n_ref"]), float(r["leak3"]),
                                           float(r["dup_within"]) + float(r["dup_cross"]))
    return d


def cer(rows):
    return 100 * sum(r[0] for r in rows) / sum(r[1] for r in rows)


def boot_diff(base, cfg, rng):
    pages = sorted(base)
    diffs = []
    for _ in range(B):
        s = [pages[rng.randrange(len(pages))] for _ in pages]
        diffs.append(cer([cfg[p] for p in s]) - cer([base[p] for p in s]))
    diffs.sort()
    return diffs[int(0.025 * B)], diffs[int(0.975 * B)]


def main():
    data = [load(p) for p in sys.argv[1:5]]
    conds = list(data[0].keys())
    groups = OrderedDict([(c, [c]) for c in conds])
    groups["ALL rotation"] = [c for c in conds if c.startswith("rot")]
    groups["ALL rotation |angle|>=3"] = [c for c in conds if c.startswith("rot") and abs(float(c[3:])) >= 3]
    groups["ALL keystone"] = [c for c in conds if c.startswith("key") or c.startswith("lightkey")]
    groups["ALL curl"] = [c for c in conds if c.startswith("curl")]
    groups["ALL conditions"] = conds
    rng = random.Random(20261029)
    lines = ["| condition | " + " | ".join(f"{n} CER% / leak3" for n in NAMES) + " | " +
             " | ".join(f"{n} - baseline [95% CI]" for n in NAMES[1:]) + " |",
             "|" + "---|" * (1 + len(NAMES) + len(NAMES) - 1)]
    csvrows = []
    for g, cs in groups.items():
        per = []
        for d in data:
            per.append({p + "|" + c: d[c][p] for c in cs for p in d[c]})
        base = per[0]
        cells, ci_cells = [], []
        for k, pd in enumerate(per):
            rows = list(pd.values())
            cells.append(f"{cer(rows):.1f} / {int(sum(r[2] for r in rows))}")
            if k:
                lo, hi = boot_diff(base, pd, rng)
                diff = cer(rows) - cer(list(base.values()))
                ci_cells.append(f"{diff:+.1f} [{lo:+.1f}, {hi:+.1f}]")
                csvrows.append(dict(group=g, config=NAMES[k], cer_base=round(cer(list(base.values())), 2), cer=round(cer(rows), 2),
                                    diff=round(diff, 2), ci_lo=round(lo, 2), ci_hi=round(hi, 2),
                                    leak3_base=int(sum(r[2] for r in base.values())), leak3=int(sum(r[2] for r in rows)),
                                    dup_base=int(sum(r[3] for r in base.values())), dup=int(sum(r[3] for r in rows))))
        lines.append(f"| {g} | " + " | ".join(cells) + " | " + " | ".join(ci_cells) + " |")
    out = "\n".join(lines)
    print(out)
    open(os.path.join(HERE, "results", "summary4.md"), "w", encoding="utf-8").write(out + "\n")
    with open(os.path.join(HERE, "results", "summary4_ci.csv"), "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(csvrows[0].keys())); w.writeheader(); w.writerows(csvrows)


if __name__ == "__main__":
    main()
