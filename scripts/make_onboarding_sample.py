#!/usr/bin/env python3
"""Prepare the onboarding sample page (first-run animation).

Source: The Tale of Genji, University of Tokyo General Library, image 01_0006 (the same
manuscript as the test sample 01_0004), right-hand page. That page has few red annotations,
so the recognition result shown in onboarding is clean.

1. Downloads the full-resolution image, crops the right-hand page, writes
   - /tmp/onboarding_source.jpg (full resolution, input for OCR)
   - KotenOCR/Assets.xcassets/OnboardingSample.imageset/onboarding_sample.jpg (1000 px wide, shipped)
2. Then run the real Koten pipeline on the full-resolution crop (boxes are stored normalized):
   TEST_RUNNER_ONBOARDING_SAMPLE_SOURCE=/tmp/onboarding_source.jpg \\
   TEST_RUNNER_ONBOARDING_SAMPLE_OUT=$PWD/KotenOCR/Resources/onboarding_sample_ocr.json \\
   xcodebuild test -scheme KotenOCR -destination 'platform=iOS Simulator,name=iPhone 17' \\
     -only-testing:KotenOCRTests/OnboardingSampleGenerator
Do not edit the JSON by hand. If a line is visibly wrong, change the crop instead.
"""
import io
import pathlib
import urllib.request

from PIL import Image

URL = "https://iiif.dl.itc.u-tokyo.ac.jp/iiif/genji/TIFF/A00_6587/01/01_0006.tif/full/full/0/default.jpg"
CROP = (3520, 900, 5980, 4170)  # right-hand page, in the 6642x4990 image
ROOT = pathlib.Path(__file__).resolve().parent.parent


def main():
    data = urllib.request.urlopen(URL).read()
    page = Image.open(io.BytesIO(data)).convert("RGB").crop(CROP)
    page.save("/tmp/onboarding_source.jpg", quality=95)
    shipped = page.resize((1000, round(1000 * page.height / page.width)), Image.LANCZOS)
    shipped.save(ROOT / "KotenOCR/Assets.xcassets/OnboardingSample.imageset/onboarding_sample.jpg",
                 quality=82, optimize=True)
    print("source", page.size, "shipped", shipped.size)


if __name__ == "__main__":
    main()
