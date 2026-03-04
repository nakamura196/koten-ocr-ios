#!/bin/bash
set -e

MODEL_DIR="KotenOCR/Models"
BASE_URL="https://raw.githubusercontent.com/ndl-lab/ndlkotenocr-lite/master/src/model"

MODELS=(
  "parseq-ndl-32x384-tiny-10.onnx"
  "rtmdet-s-1280x1280.onnx"
)

mkdir -p "$MODEL_DIR"

for model in "${MODELS[@]}"; do
  if [ -f "$MODEL_DIR/$model" ]; then
    echo "Already exists: $model"
  else
    echo "Downloading: $model ..."
    curl -L -o "$MODEL_DIR/$model" "$BASE_URL/$model"
    echo "Done: $model"
  fi
done

echo "Setup complete."
