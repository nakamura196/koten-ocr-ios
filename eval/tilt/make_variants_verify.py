"""Verification variants (VERIFY.md): same 19 conditions/parameters as make_variants.py, applied to pages_selected_verify.csv.
Seed logic is identical (Random(f"{SEED}/{page_id}/{condition}")) but SEED is the verification seed 20261031.
Output: data/variants_verify/<page_id>__<condition>.jpg, manifest_verify.csv (same columns as manifest.csv).
Run: python -I make_variants_verify.py
"""
import csv, hashlib, json, os, random
import cv2
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_variants as mv

HERE = mv.HERE
OUT = os.path.join(HERE, "data", "variants_verify")
SEED = 20261031


def main():
    os.makedirs(OUT, exist_ok=True)
    sel = list(csv.DictReader(open(os.path.join(HERE, "pages_selected_verify.csv"), encoding="utf-8")))
    rows = []
    for s in sel:
        pid = s["page_id"]
        img = cv2.imread(os.path.join(mv.PAGES, pid + ".jpg"), cv2.IMREAD_COLOR)
        pad = mv.paper_colour(img)
        for name, family, p in mv.conditions():
            rng = random.Random(f"{SEED}/{pid}/{name}")
            out, extra = mv.apply(img, family, p, pad, rng)
            fn = f"{pid}__{name}.jpg"
            path = os.path.join(OUT, fn)
            cv2.imwrite(path, out, [cv2.IMWRITE_JPEG_QUALITY, mv.JPEG_QUALITY])
            sha = hashlib.sha256(open(path, "rb").read()).hexdigest()
            rows.append(dict(
                image_file=f"data/variants_verify/{fn}", page_id=pid, book_id=s["book_id"], book_title=s["book_title"],
                source_url=s["source_zip_url"], source_member=f"{s['book_id']}/images/{pid}.jpg",
                licence="CC BY-SA 4.0", attribution=mv.ATTRIBUTION, condition=name, family=family,
                params_json=json.dumps(dict(p, **extra), ensure_ascii=False, sort_keys=True),
                pad_rgb="%d,%d,%d" % (pad[2], pad[1], pad[0]), seed=SEED,
                src_w=img.shape[1], src_h=img.shape[0], out_w=out.shape[1], out_h=out.shape[0], sha256=sha))
    with open(os.path.join(HERE, "manifest_verify.csv"), "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)
    print("wrote", len(rows), "images")


if __name__ == "__main__":
    main()
