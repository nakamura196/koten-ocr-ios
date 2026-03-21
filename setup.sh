#!/bin/bash
set -e

MODEL_DIR="KotenOCR/Models"

# --- NDL Koten OCR-Lite (classical Japanese) ---
KOTEN_BASE_URL="https://raw.githubusercontent.com/ndl-lab/ndlkotenocr-lite/master/src/model"

KOTEN_MODELS=(
  "parseq-ndl-32x384-tiny-10.onnx"
  "rtmdet-s-1280x1280.onnx"
)

mkdir -p "$MODEL_DIR"

for model in "${KOTEN_MODELS[@]}"; do
  if [ -f "$MODEL_DIR/$model" ]; then
    echo "Already exists: $model"
  else
    echo "Downloading (Koten): $model ..."
    curl -L -o "$MODEL_DIR/$model" "$KOTEN_BASE_URL/$model"
    echo "Done: $model"
  fi
done

# --- NDLOCR-Lite (modern Japanese) ---
NDL_BASE_URL="https://raw.githubusercontent.com/ndl-lab/ndlocr-lite/master/src/model"
NDL_CONFIG_URL="https://raw.githubusercontent.com/ndl-lab/ndlocr-lite/master/src/config"

NDL_MODELS=(
  "deim-s-1024x1024.onnx"
  "parseq-ndl-16x256-30-tiny-192epoch-tegaki3.onnx"
  "parseq-ndl-16x384-50-tiny-146epoch-tegaki2.onnx"
  "parseq-ndl-16x768-100-tiny-165epoch-tegaki2.onnx"
)

for model in "${NDL_MODELS[@]}"; do
  if [ -f "$MODEL_DIR/$model" ]; then
    echo "Already exists: $model"
  else
    echo "Downloading (NDL): $model ..."
    curl -L -o "$MODEL_DIR/$model" "$NDL_BASE_URL/$model"
    echo "Done: $model"
  fi
done

# Download NDLOCR-Lite config as ndl-deim.yaml (avoid collision with koten ndl.yaml)
if [ -f "$MODEL_DIR/ndl-deim.yaml" ]; then
  echo "Already exists: ndl-deim.yaml"
else
  echo "Downloading (NDL): ndl.yaml -> ndl-deim.yaml ..."
  curl -L -o "$MODEL_DIR/ndl-deim.yaml" "$NDL_CONFIG_URL/ndl.yaml"
  echo "Done: ndl-deim.yaml"
fi

echo "Setup complete."
