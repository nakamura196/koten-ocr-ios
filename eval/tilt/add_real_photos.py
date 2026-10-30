"""Register real photos (see REAL_PHOTOS.md) in real_manifest.csv so that measure.py can score them.

Photos live in data/real/ and are named  <page_id>__<camera_angle>deg.jpg  e.g. 200015843_00031_1__20deg.jpg
(page_id comes from pages_selected.csv).  The reference text of that page then applies unchanged.

    python -I add_real_photos.py
    python -I measure.py --manifest real_manifest.csv --deskew off --out results/real_baseline.csv
"""
import csv
import hashlib
import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
REAL = os.path.join(HERE, "data", "real")
sel = {r["page_id"]: r for r in csv.DictReader(open(os.path.join(HERE, "pages_selected.csv"), encoding="utf-8"))}
ATTR = ("『日本古典籍くずし字データセット』（国文研ほか所蔵／CODH加工） doi:10.20676/00000340, CC BY-SA 4.0; "
        "page printed on paper and photographed by the repository author")
rows = []
for fn in sorted(os.listdir(REAL)):
    m = re.fullmatch(r"(.+)__(\d+)deg\.(jpg|jpeg)", fn, re.I)
    if not m:
        print("skip (name does not match <page_id>__<angle>deg.jpg):", fn)
        continue
    pid, ang = m.group(1), int(m.group(2))
    if pid not in sel:
        print("skip (page_id not in pages_selected.csv):", fn)
        continue
    s = sel[pid]
    sha = hashlib.sha256(open(os.path.join(REAL, fn), "rb").read()).hexdigest()
    rows.append(dict(image_file=f"data/real/{fn}", page_id=pid, book_id=s["book_id"], book_title=s["book_title"],
                     source_url=s["source_zip_url"], source_member=f"{s['book_id']}/images/{pid}.jpg",
                     licence="CC BY-SA 4.0", attribution=ATTR, condition=f"real{ang}deg", family="real",
                     params_json=json.dumps(dict(camera_angle_deg=ang), sort_keys=True), pad_rgb="", seed="",
                     src_w="", src_h="", out_w="", out_h="", sha256=sha))
with open(os.path.join(HERE, "real_manifest.csv"), "w", newline="", encoding="utf-8") as f:
    w = csv.DictWriter(f, fieldnames=list(rows[0].keys()) if rows else ["image_file"])
    w.writeheader()
    w.writerows(rows)
print("registered", len(rows), "photos")
