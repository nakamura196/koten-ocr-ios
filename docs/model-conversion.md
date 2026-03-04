# Python → ONNX モデル変換ガイド

KotenOCR で使用する2つのモデルの変換手順を記載する。

## 前提

- 変換済みモデルは [ndl-lab/ndlkotenocr-lite](https://github.com/ndl-lab/ndlkotenocr-lite) の `src/model/` からダウンロード可能
- 自分で変換する必要がなければ `setup.sh` でダウンロードするだけでよい
- 以下はモデルを再学習・カスタマイズした場合の変換手順

---

## 1. RTMDet（テキスト検出モデル）

### 概要

| 項目 | 値 |
|------|-----|
| アーキテクチャ | RTMDet-S (CSPNeXt backbone) |
| フレームワーク | PyTorch + MMDetection 3.0 + MMDeploy 1.3.1 |
| 入力 | `[1, 3, 1024, 1024]` float32 |
| 出力 | `dets [1, N, 5]` (x1,y1,x2,y2,score) + `labels [1, N]` |
| 特徴 | NMS がONNXグラフに組み込み済み |

### 環境構築

```bash
pip install torch==2.0.0 --index-url https://download.pytorch.org/whl/cu118
pip install mmcv==2.0.0 -f https://download.openmmlab.com/mmcv/dist/cu118/torch2.0/index.html
pip install mmdet==3.0.0
pip install mmdeploy==1.3.1
pip install onnx==1.16.2 onnxruntime==1.18.1
```

### 変換コマンド

```bash
python3 mmdeploy/tools/deploy.py \
    ./rtmonnx_config.py \
    ./mmdetv3-rtmdet_s_8xb32-300e_coco_sample.py \
    ./work_dir_mmdetv3_rtmdet_s/epoch_300.pth \
    ./sample_image.jpg \
    --work-dir mmdeploy_model/rtmdet_s
```

### ONNX エクスポート設定 (`rtmonnx_config.py`)

```python
onnx_config = dict(
    type='onnx',
    export_params=True,
    keep_initializers_as_inputs=False,
    opset_version=17,
    save_file='rtmdet-s-1280x1280.onnx',
    input_names=['input'],
    output_names=['dets', 'labels'],
    input_shape=[1024, 1024],
    optimize=True)

codebase_config = dict(
    type='mmdet',
    task='ObjectDetection',
    model_type='end2end',
    post_processing=dict(
        score_threshold=0.01,
        confidence_threshold=0.001,
        iou_threshold=0.3,
        max_output_boxes_per_class=300,
        pre_top_k=3000,
        keep_top_k=300,
        background_label_id=-1))

backend_config = dict(
    type='onnxruntime',
    model_inputs=[dict(input_shapes=dict(input=[1, 3, 1024, 1024]))])
```

### 注意: ファイル名と入力サイズの不一致

上流リポジトリのファイル名は `rtmdet-s-1280x1280.onnx` だが、実際のモデル入力サイズは `[1, 3, 1024, 1024]` である。ファイル名は上流に合わせてそのまま使用する。

### 難易度

**やや複雑** — MMDeploy のバージョン依存が強く、環境構築に手間がかかる。ただしコマンド自体は1行で完了する。

---

## 2. PARSeq（テキスト認識モデル）

### 概要

| 項目 | 値 |
|------|-----|
| アーキテクチャ | PARSeq-Tiny (Transformer encoder-decoder) |
| フレームワーク | PyTorch + PyTorch Lightning ([baudm/parseq](https://github.com/baudm/parseq)) |
| 入力 | `[1, 3, 32, 384]` float32 |
| 出力 | `[1, 101, 7142]` float32 (101=最大長+1, 7142=文字数+EOS) |
| 文字セット | NDLmoji.yaml (7141文字) |

### 環境構築

```bash
git clone https://github.com/baudm/parseq.git
cd parseq
pip install -r requirements.txt
pip install onnx
```

### 変換前の修正（必須）

`strhub/models/parseq/model.py` の117行目を修正:

```python
# 変更前
dtype=torch.bool
# 変更後
dtype=torch.float
```

これを行わないと ONNX エクスポート時に `CumSum` 演算でエラーになる。

### 変換スクリプト (`convert2onnx.py`)

```python
import torch
import yaml
from strhub.models.utils import load_from_checkpoint

# 文字セット読み込み
with open('./configs/charset/NDLmoji.yaml', 'r') as f:
    config = yaml.safe_load(f)

# モデル読み込み
checkpoint = './path_to_checkpoint.ckpt'
kwargs = {'charset_test': config["model"]["charset_test"]}
model = load_from_checkpoint(checkpoint, **kwargs).eval().to('cpu')

# エクスポート設定
model.refine_iters = 10    # 推論時のリファイン回数
model.decode_ar = True      # 自己回帰デコーディング

# ONNX 変換
model.to_onnx(
    "parseq-ndl-32x384-tiny-10.onnx",
    torch.randn([1, 3, 32, 384]),
    do_constant_folding=True,
    opset_version=17
)
```

### 難易度

**簡単** — PyTorch Lightning の `to_onnx()` メソッド1つで完了。ただし上記の `torch.bool → torch.float` 修正を忘れないこと。

---

## 3. 変換後の検証

```python
import onnxruntime as ort
import numpy as np

# モデル読み込み確認
session = ort.InferenceSession("model.onnx")
for inp in session.get_inputs():
    print(f"Input: {inp.name}, shape: {inp.shape}, dtype: {inp.type}")
for out in session.get_outputs():
    print(f"Output: {out.name}, shape: {out.shape}, dtype: {out.type}")

# ダミー推論
dummy = np.random.randn(1, 3, 1024, 1024).astype(np.float32)  # RTMDet
# dummy = np.random.randn(1, 3, 32, 384).astype(np.float32)   # PARSeq
result = session.run(None, {session.get_inputs()[0].name: dummy})
print([r.shape for r in result])
```

## 4. iOS アプリへの配置

変換した `.onnx` ファイルを `KotenOCR/Models/` に配置し、`setup.sh` のダウンロード処理と同等の構成にする。

```
KotenOCR/Models/
├── rtmdet-s-1280x1280.onnx      # 検出モデル (~40MB)
├── parseq-ndl-32x384-tiny-10.onnx # 認識モデル (~38MB)
├── ndl.yaml                       # 推論設定
└── NDLmoji.yaml                   # 文字セット定義
```
