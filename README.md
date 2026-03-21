# KotenOCR

古典籍・くずし字と近代活字をAIで読み取るiOS OCRアプリ。

国立国会図書館の [NDL古典籍OCR-Lite](https://github.com/ndl-lab/ndlkotenocr-lite) および [NDLOCR-Lite](https://github.com/ndl-lab/ndlocr-lite) モデルを搭載し、すべての処理をデバイス上で完結します。インターネット接続は不要です。

[![App Store](https://img.shields.io/badge/App%20Store-Download-blue?logo=apple&logoColor=white)](https://apps.apple.com/jp/app/kotenocr/id6760045646)

![App Store Screenshots](screenshots/marketing_combined.png)

## 機能

- **2つのOCRモード** — 古典籍（くずし字）と近代（活字・手書き）を切り替えて使用
- **カメラ撮影 / フォトライブラリ** — 古典籍のページを撮影または選択してOCR実行
- **フラッシュ / タップフォーカス** — 暗所撮影やピント調整に対応
- **認識結果の閲覧** — 検出領域のボックス表示、ピンチズーム、タップ選択
- **テキスト編集** — 認識結果を長押しで手動修正
- **エクスポート** — テキスト共有 / TXT / PDF での書き出し
- **スキャン履歴** — OCR結果を自動保存、一覧から再表示・削除
- **テーマ切替** — ダーク / ライト / システム準拠
- **多言語対応** — 日本語 / English / システム設定
- **アクセシビリティ** — VoiceOver対応
- **現代語訳** — 古文を現代語に翻訳（日本語/英語、3段階の解説レベル）
  - **ローカルAI（Apple Foundation Models）** — iOS 26+対応デバイスでオンデバイス翻訳（インターネット不要）
  - **クラウドAPI** — OpenAI互換API（OpenRouter / OpenAI / カスタム）
- **応援（Tip Jar）** — StoreKit 2によるアプリ内課金

## OCRモード

| モード | 対象 | 検出モデル | 認識モデル |
|--------|------|-----------|-----------|
| 古典籍 | くずし字・変体仮名 | RTMDet-S | PARSeq (1モデル) |
| 近代 | 活字・手書き文字 | DEIMv2-S | PARSeq カスケード (3モデル) |

認識処理は並列化されており、近代モードでは最大6.7倍の高速化を実現しています。

## 要件

- iOS 16.0+
- Xcode 15.0+
- Swift 5.9

## セットアップ

```bash
# リポジトリをクローン
git clone https://github.com/nakamura196/koten-ocr-ios.git
cd koten-ocr-ios

# ONNXモデルをダウンロード（古典籍 + 近代、合計約230MB）
./setup.sh

# Xcodeプロジェクトを生成
xcodegen generate

# Xcodeで開く
open KotenOCR.xcodeproj
```

### ONNXモデル

以下のモデルを `KotenOCR/Models/` に配置する必要があります（`.gitignore` で除外済み、`setup.sh` で自動ダウンロード）：

#### 古典籍モード（NDL古典籍OCR-Lite）

| モデル | ファイル名 | サイズ |
|--------|-----------|--------|
| テキスト検出（RTMDet-S） | `rtmdet-s-1280x1280.onnx` | ~40MB |
| 文字認識（PARSeq） | `parseq-ndl-32x384-tiny-10.onnx` | ~38MB |

#### 近代モード（NDLOCR-Lite）

| モデル | ファイル名 | サイズ |
|--------|-----------|--------|
| レイアウト検出（DEIMv2-S） | `deim-s-1024x1024.onnx` | ~38MB |
| 文字認識 30文字（PARSeq） | `parseq-ndl-16x256-30-tiny-192epoch-tegaki3.onnx` | ~34MB |
| 文字認識 50文字（PARSeq） | `parseq-ndl-16x384-50-tiny-146epoch-tegaki2.onnx` | ~35MB |
| 文字認識 100文字（PARSeq） | `parseq-ndl-16x768-100-tiny-165epoch-tegaki2.onnx` | ~39MB |

## ビルド & アーカイブ

```bash
# デバッグビルド
xcodebuild build \
  -project KotenOCR.xcodeproj \
  -scheme KotenOCR \
  -destination 'generic/platform=iOS'

# App Store用アーカイブ
./scripts/archive.sh
```

## ライセンス

### OCRモデル
- **NDL古典籍OCR-Lite** — [CC-BY-4.0](https://creativecommons.org/licenses/by/4.0/) （国立国会図書館）
- **NDLOCR-Lite** — [CC-BY-4.0](https://creativecommons.org/licenses/by/4.0/) （国立国会図書館）

### 依存ライブラリ
- **ONNX Runtime** — [MIT License](https://github.com/microsoft/onnxruntime/blob/main/LICENSE) （Microsoft）
