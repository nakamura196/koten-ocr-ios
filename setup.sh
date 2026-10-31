#!/bin/bash
set -e

MODEL_DIR="KotenOCR/Models"

# Models are pinned to upstream commits so a fresh checkout gets the same files as the
# release. A file whose size does not match (e.g. an older download) is fetched again.
# NDL replaced the koten recognition model on 2026-02-16 ("suspected corrupted model",
# 8cac954, 42442247 bytes). On our pages the replacement read no better and sometimes
# produced stray ASCII lines, so the app keeps the original until it is evaluated properly.
KOTEN_COMMIT="95692df82f15b5fc225cbbc5134d2efc3cfb522d"
# Last ndlocr-lite commit with the 16px-high PARSeq models the app reads.
NDL_COMMIT="109e62759d59002673765e0f7f2cfc663443585d"

# fetch <base url> <file> <expected size> [<local name>]
fetch() {
  local url="$1/$2" dest="$MODEL_DIR/${4:-$2}" size="$3"
  if [ -f "$dest" ] && [ "$(stat -f%z "$dest" 2>/dev/null || stat -c%s "$dest")" = "$size" ]; then
    echo "Already exists: ${4:-$2}"
    return
  fi
  echo "Downloading: $2 ..."
  curl -fL -o "$dest" "$url"
  local got
  got=$(stat -f%z "$dest" 2>/dev/null || stat -c%s "$dest")
  if [ "$got" != "$size" ]; then
    echo "Size mismatch for $2: expected $size, got $got" >&2
    exit 1
  fi
  echo "Done: ${4:-$2}"
}

mkdir -p "$MODEL_DIR"

# --- NDL Koten OCR-Lite (classical Japanese) ---
KOTEN_BASE_URL="https://raw.githubusercontent.com/ndl-lab/ndlkotenocr-lite/$KOTEN_COMMIT/src/model"
fetch "$KOTEN_BASE_URL" parseq-ndl-32x384-tiny-10.onnx 37752180
fetch "$KOTEN_BASE_URL" rtmdet-s-1280x1280.onnx 40188733

# --- NDLOCR-Lite (modern Japanese) ---
NDL_BASE_URL="https://raw.githubusercontent.com/ndl-lab/ndlocr-lite/$NDL_COMMIT/src/model"
fetch "$NDL_BASE_URL" deim-s-1024x1024.onnx 40256763
fetch "$NDL_BASE_URL" parseq-ndl-16x256-30-tiny-192epoch-tegaki3.onnx 35848117
fetch "$NDL_BASE_URL" parseq-ndl-16x384-50-tiny-146epoch-tegaki2.onnx 36920058
fetch "$NDL_BASE_URL" parseq-ndl-16x768-100-tiny-165epoch-tegaki2.onnx 40984184

# NDLOCR-Lite config is tracked in git as ndl-deim.yaml (avoids collision with koten ndl.yaml).

echo "Setup complete."
