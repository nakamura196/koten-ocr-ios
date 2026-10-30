"""Summary table by condition from one or more measure.py CSVs.

    python -I summarize.py results/baseline.csv results/deskew.csv > results/summary.md

CER per condition is micro-averaged (sum of edit distances / sum of reference lengths over the pages).
Leak / dup columns are totals over the pages of that condition.
"""
import csv
import os
import sys
from collections import OrderedDict, defaultdict


def load(path):
    rows = list(csv.DictReader(open(path, encoding="utf-8")))
    agg = OrderedDict()
    for r in rows:
        a = agg.setdefault(r["condition"], defaultdict(float))
        a["n"] += 1
        a["edit"] += float(r["edit"]); a["ref"] += float(r["n_ref"])
        a["bag"] += float(r["bag_cer"]) * float(r["n_ref"])
        for k in ("leak3", "leak5", "dup_within", "dup_cross"):
            a[k] += float(r[k])
        a["ang"] += float(r["deskew_angle"])
    return agg


def main():
    paths = sys.argv[1:]
    names = [os.path.splitext(os.path.basename(p))[0] for p in paths]
    data = [load(p) for p in paths]
    conds = list(data[0].keys())
    head = ["condition", "pages"]
    for n in names:
        head += [f"{n} CER%", f"{n} bagCER%", f"{n} leak3", f"{n} leak5", f"{n} dup"]
    print("| " + " | ".join(head) + " |")
    print("|" + "---|" * len(head))
    for c in conds:
        row = [c, str(int(data[0][c]["n"]))]
        for d in data:
            a = d.get(c)
            if not a:
                row += ["-"] * 5
                continue
            row += [f"{100 * a['edit'] / a['ref']:.1f}", f"{100 * a['bag'] / a['ref']:.1f}",
                    f"{int(a['leak3'])}", f"{int(a['leak5'])}", f"{int(a['dup_within'] + a['dup_cross'])}"]
        print("| " + " | ".join(row) + " |")
    # family totals
    print()
    fam = {}
    for p, n in zip(paths, names):
        for r in csv.DictReader(open(p, encoding="utf-8")):
            f = fam.setdefault((r["family"], n), defaultdict(float))
            f["edit"] += float(r["edit"]); f["ref"] += float(r["n_ref"])
            f["leak3"] += float(r["leak3"]); f["n"] += 1
    print("| family | " + " | ".join(f"{n} CER% / leak3" for n in names) + " |")
    print("|---|" + "---|" * len(names))
    for fm in OrderedDict.fromkeys(k[0] for k in fam):
        print(f"| {fm} | " + " | ".join(
            f"{100 * fam[(fm, n)]['edit'] / fam[(fm, n)]['ref']:.1f} / {int(fam[(fm, n)]['leak3'])}" for n in names) + " |")


if __name__ == "__main__":
    main()
