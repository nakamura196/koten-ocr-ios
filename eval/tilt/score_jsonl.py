"""Score recognised lines written by another runner (the iOS app's EvalTiltTests) with measure.py's metrics.

    data/venv/bin/python -I score_jsonl.py --manifest manifest.csv --hyp results/app_sim.hyp.jsonl --out results/app_sim.csv

The JSONL has one object per image: {"image_file": ..., "lines": [{"box", "score", "text"}, ...], "secs": ...}, lines in
the app's reading order. References are data/pages/<page_id>.json as for measure.py. Writes the per-image CSV (same
columns as measure.py; deskew_angle is empty because the app does not report it) and prints a per-condition table:
CER micro-averaged over pages, leak3/leak5 and dup totals.
"""
import argparse
import csv
import json
import os
import sys
from collections import OrderedDict, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from measure import normalise, score  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--manifest", default=os.path.join(HERE, "manifest.csv"))
    ap.add_argument("--hyp", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    rows = {r["image_file"]: r for r in csv.DictReader(open(a.manifest, encoding="utf-8"))}
    hyps = [json.loads(l) for l in open(a.hyp, encoding="utf-8") if l.strip()]
    missing = set(rows) - {h["image_file"] for h in hyps}
    if missing:
        print(f"warning: {len(missing)} manifest images have no hypothesis", file=sys.stderr)
    out = []
    for h in hyps:
        r = rows[h["image_file"]]
        ref = json.load(open(os.path.join(HERE, "data", "pages", r["page_id"] + ".json"), encoding="utf-8"))
        ref_lines = [l["text"] for l in ref["lines"]]
        m = score([l["text"] for l in h["lines"]], ref_lines)
        out.append(dict(image_file=h["image_file"], page_id=r["page_id"], book_id=r["book_id"], condition=r["condition"],
                        family=r["family"], n_det=len(h["lines"]), n_ref_lines=len([l for l in ref_lines if normalise(l)]),
                        deskew_angle="", secs=h.get("secs", ""), **m))
    with open(a.out, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(out[0].keys()))
        w.writeheader()
        w.writerows(out)
    by = OrderedDict()
    for r in out:
        by.setdefault(r["condition"], []).append(r)
    fam = defaultdict(list)
    print("| condition | pages | CER% | bagCER% | leak3 | leak5 | dup |")
    print("|---|---|---|---|---|---|---|")
    for c, rs in by.items():
        fam[rs[0]["family"]] += rs
        print(f"| {c} | {len(rs)} | {cer(rs):.1f} | {100 * sum(r['bag_cer'] * r['n_ref'] for r in rs) / sum(r['n_ref'] for r in rs):.1f} "
              f"| {sum(r['leak3'] for r in rs)} | {sum(r['leak5'] for r in rs)} | {sum(r['dup_within'] + r['dup_cross'] for r in rs)} |")
    print()
    print("| family | CER% | leak3 |")
    print("|---|---|---|")
    for f_, rs in fam.items():
        print(f"| {f_} | {cer(rs):.1f} | {sum(r['leak3'] for r in rs)} |")
    print(f"\nall {len(out)} images: CER {cer(out):.1f}%, leak3 {sum(r['leak3'] for r in out)}")


def cer(rs):
    return 100 * sum(r["edit"] for r in rs) / sum(r["n_ref"] for r in rs)


if __name__ == "__main__":
    main()
