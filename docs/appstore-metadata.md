# App Store メタデータ

App Store Connect でアプリを作成する際に入力する情報。

## 基本情報

| 項目 | 値 |
|------|-----|
| アプリ名 | KotenOCR |
| サブタイトル | 古典籍・くずし字OCR |
| Bundle ID | com.nakamura196.kotenocr |
| SKU | kotenocr |
| プライマリ言語 | 日本語 |
| カテゴリ(Primary) | ユーティリティ |
| カテゴリ(Secondary) | 教育 |
| コンテンツの権利 | 第三者のコンテンツを使用（NDL古典籍OCR-Lite: CC-BY-4.0） |
| 年齢制限 | 4+ |
| 価格 | 無料 |

## 説明文（日本語）

```
古典籍のくずし字をAIで読み取るOCRアプリです。

【特徴】
・カメラで撮影するだけで、くずし字をテキストに変換
・国立国会図書館のAIモデル（NDL古典籍OCR-Lite）を搭載
・すべての処理をデバイス上で完結（インターネット接続不要）
・認識結果をテキストとしてコピー・共有
・古文を現代語訳（日本語/英語対応、一般・学生・研究者向けの3段階解説）
・ローカルAI翻訳（iOS 26+対応デバイスで完全オフライン動作）
・クラウドAPI翻訳にも対応（OpenAI、OpenRouter等）

【使い方】
1. カメラで古典籍のページを撮影、またはフォトライブラリから選択
2. AIが自動でテキスト領域を検出し、くずし字を認識
3. 認識結果をタップして確認、コピーして活用

【対応文字】
7000文字以上の漢字・ひらがな・カタカナに対応。江戸期の版本・写本を中心に高い認識精度を実現しています。

【ライセンス】
・OCRモデル: NDL古典籍OCR-Lite（国立国会図書館, CC-BY-4.0）
・推論エンジン: ONNX Runtime（Microsoft, MIT License）
```

## 説明文（英語）

```
An OCR app that reads classical Japanese cursive script (kuzushiji) using AI.

Features:
• Just take a photo to convert kuzushiji to text
• Powered by the National Diet Library's AI model (NDL Koten OCR-Lite)
• All processing runs on-device (no internet connection required)
• Copy and share recognized text
• Translate classical text into modern Japanese or English (3 detail levels: general, student, researcher)
• On-device AI translation with Apple Foundation Models (iOS 26+, fully offline)
• Also supports cloud APIs (OpenAI, OpenRouter, etc.)

How to Use:
1. Capture a page with the camera or select from your photo library
2. AI automatically detects text regions and recognizes kuzushiji
3. Tap results to review, copy and use

Supports over 7,000 kanji, hiragana, and katakana characters. Optimized for Edo-period woodblock prints and manuscripts.

Licenses:
• OCR Model: NDL Koten OCR-Lite (National Diet Library, CC-BY-4.0)
• Inference Engine: ONNX Runtime (Microsoft, MIT License)
```

## キーワード（日本語、最大100文字）

```
OCR,くずし字,古典籍,文字認識,古文書,和本,国立国会図書館,NDL,現代語訳,オフライン
```

## キーワード（英語）

```
OCR,kuzushiji,classical,Japanese,manuscript,recognition,NDL,translation,kanji,text
```

## プロモーションテキスト（日本語、170文字以内）

```
古典籍のくずし字をAIが読み取り、現代語訳まで完全オフラインで。国立国会図書館のOCRモデルとApple Foundation Modelsを搭載し、古文の意味・背景もAIが解説します。
```

## サポートURL

```
https://github.com/nakamura196/koten-ocr-ios
```

## プライバシーポリシーURL

App Store 提出時に公開URLが必要。GitHub Pages 等にホストする:
```
https://nakamura196.github.io/koten-ocr-ios/privacy-policy.html
```

## App Storeプレビュー動画

| 項目 | 仕様 |
|------|------|
| 形式 | MP4 (H.264) |
| 最大長 | 30秒 |
| デバイス | iPhone 6.7" (iPhone 17 Pro Max) |
| 言語 | 日本語 / 英語 |

デモ動画は `scripts/record_demo_video.sh` で自動生成。古典籍OCRと近代OCRの両モードを紹介。

<video src="../screenshots/demo_v130.mp4" controls muted playsinline width="300"></video>

### 動画の内容

1. スプラッシュ画面（アプリ起動）
2. 古典籍OCR結果（くずし字の認識）
3. 現代語訳（翻訳タブ）
4. クロップ画面（校異源氏物語の画像選択）
5. 近代OCRモード選択
6. 近代OCR結果（活字の認識）

### 動画の生成・アップロード

```bash
# 録画（古典籍+近代の統合動画）
./scripts/record_demo_video.sh --mode combined

# App Store Connectへアップロード（PREPARE_FOR_SUBMISSION状態のバージョンが必要）
python3 scripts/upload_preview.py --video /tmp/kotenocr_videos/demo_ja_combined_iphone.mp4 --lang ja
```

## スクリーンショット要件

| デバイス | サイズ | 必須 |
|---------|--------|------|
| iPhone 6.7" (15 Pro Max) | 1290 x 2796 | 必須 |
| iPhone 6.1" (15 Pro) | 1179 x 2556 | 推奨 |
| iPad 12.9" (6th gen) | 2048 x 2732 | iPad対応なら必須 |

### スクリーンショット案（最低3枚）

1. **カメラ画面**: 古典籍にカメラを向けている場面
2. **認識結果**: テキスト検出ボックスと認識結果が表示された画面
3. **テキストリスト**: 認識されたテキスト一覧（コピー可能）
4. **オンボーディング**: アプリ紹介画面
5. **設定/ライセンス**: ライセンス表記画面

## App Review 向けメモ

```
This app performs OCR on classical Japanese texts (kuzushiji) using on-device AI models.
No account or login is required.
To test OCR: point the camera at any printed text or select an image from the photo library.
The app will detect text regions and attempt recognition.
To test translation: go to Settings > Translation Settings. On iOS 26+ devices, "Local AI (Apple)" is available by default with no API key needed. For cloud API translation, select OpenRouter or OpenAI and enter an API key. Then tap "Modern Translation" on any OCR result.
Sample images of classical Japanese texts can be found at: https://dl.ndl.go.jp/
```
