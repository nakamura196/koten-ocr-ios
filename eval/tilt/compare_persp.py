"""CER % / leak3 by condition group, without vs with the four-corner perspective correction (persp.py).

Usage: data/venv/bin/python -I compare_persp.py [prefix]   # prefix '' = tuning set, e.g. 'heldout_' or 'verify_'
Reads results/<prefix>{perline,deskew_perline,deskew_perline_nogate}.csv and results/<prefix>persp_*.csv.
"""
import csv, os, sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
GROUPS = [("all", lambda c: True), ("rot±3..8", lambda c: c.startswith("rot") and abs(float(c[3:])) >= 3),
          ("rot+0", lambda c: c == "rot+0.0"), ("key±1", lambda c: c in ("key-up1", "key-down1")),
          ("key±2", lambda c: c in ("key-up2", "key-down2")), ("key±3", lambda c: c in ("key-up3", "key-down3")),
          ("curl", lambda c: c.startswith("curl")), ("lightkey", lambda c: c.startswith("lightkey"))]
RUNS = [("deskew off", "perline"), ("deskew, gate on", "deskew_perline"), ("deskew, gate off", "deskew_perline_nogate")]


def row(path):
    agg = defaultdict(lambda: [0.0, 0.0, 0])
    for r in csv.DictReader(open(path, encoding="utf-8")):
        for g, f in GROUPS:
            if f(r["condition"]):
                a = agg[g]; a[0] += float(r["edit"]); a[1] += float(r["n_ref"]); a[2] += int(float(r["leak3"]))
    return " | ".join(f"{100 * agg[g][0] / agg[g][1]:.1f} / {agg[g][2]}" for g, _ in GROUPS)


def main(prefix=""):
    print("| perspective | rotation | " + " | ".join(g for g, _ in GROUPS) + " |")
    print("|---" * (len(GROUPS) + 2) + "|")
    for tag, pre in (("none", prefix), ("4 corners", prefix + "persp_")):
        for name, f in RUNS:
            p = os.path.join(HERE, "results", f"{pre}{f}.csv")
            if os.path.exists(p):
                print(f"| {tag} | {name} | {row(p)} |")


if __name__ == "__main__":
    main(*sys.argv[1:2])
