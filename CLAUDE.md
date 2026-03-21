# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

KotenOCR — iOS app for OCR of classical Japanese texts (くずし字/kuzushiji). Uses ONNX Runtime to run NDL古典籍OCR-Lite models entirely on-device. No internet required for core OCR.

- **Bundle ID**: `com.nakamura196.kotenocr`
- **Deployment target**: iOS 16.0+
- **Language**: Swift 5.9, SwiftUI

## Build Commands

```bash
# Initial setup: download ONNX models (~80MB)
./setup.sh

# Generate Xcode project (if project.yml changes)
xcodegen generate

# Debug build
xcodebuild build -project KotenOCR.xcodeproj -scheme KotenOCR -destination 'generic/platform=iOS'

# Build for simulator (iPad Pro 13-inch)
xcodebuild build -project KotenOCR.xcodeproj -scheme KotenOCR -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)'

# Archive for App Store
xcodebuild -project KotenOCR.xcodeproj -scheme KotenOCR -configuration Release -archivePath /tmp/KotenOCR.xcarchive archive -allowProvisioningUpdates

# Export & upload to App Store Connect
xcodebuild -exportArchive -archivePath /tmp/KotenOCR.xcarchive -exportOptionsPlist ExportOptions.plist -exportPath /tmp/KotenOCR_export -allowProvisioningUpdates
```

```bash
# Run tests (simulator required)
xcodebuild test -project KotenOCR.xcodeproj -scheme KotenOCR \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' \
  -only-testing:KotenOCRTests
```

No linter configured.

## Architecture

### OCR Pipeline (KotenOCR/OCR/)

デュアルモードアーキテクチャ。起動時に両モードのモデルをすべてロードし、ユーザーが確認画面で選択する。

#### Koten（古典籍）モード
1. **Detection** — `RTMDetector` runs RTMDet-S model (1024x1024 input)
2. **Recognition** — `PARSEQRecognizer` runs PARSeq-Tiny (384x32 input), NDLmoji charset (7141 chars)
3. **Reading Order** — `ReadingOrderProcessor` applies block_xy_cut

#### NDL（近代）モード
1. **Detection** — `DEIMDetector` runs DEIMv2-S model (800x800 input, 2 inputs: image + orig_size, 17 classes)
2. **Recognition** — `CascadePARSEQRecognizer` routes to 3 models based on predicted char count:
   - predCharCount==3 → 30-char model (16x256)
   - predCharCount==2 → 50-char model (16x384)
   - else → 100-char model (16x768)
3. **Reading Order** — same `ReadingOrderProcessor`

認識処理は `withThrowingTaskGroup` で並列実行（近代モードで最大6.7倍高速化）。

`OCREngine` is an `@MainActor ObservableObject` with states: `.uninitialized` → `.loading` → `.ready` / `.error`. Both model sets load at startup.

### App State Machine (ContentView)

`AppState` enum drives the main UI flow:
```text
.camera → .cropping → .confirmCrop → .processing → .result
```
- `.camera` — CameraView (AVFoundation) + PhotosPicker
- `.cropping` — CropView with drag handles
- `.confirmCrop` — Preview before OCR with mode selection buttons (古典籍/近代)
- `.processing` — Shows progress, cancellable
- `.result` — ResultOverlayView with box overlay, text editing, export, translation. Back button returns to `.confirmCrop` for re-OCR with different mode

### Translation (KotenOCR/Translation/)

`TranslationService` is a Swift `actor` supporting:
- **Local AI**: Apple Foundation Models (iOS 26+ only, `@available` gated)
- **Cloud APIs**: OpenAI-compatible endpoints (OpenAI, OpenRouter, custom URL)
- API keys stored in Keychain via `KeychainHelper`

### Key Data Models

- `Detection` — Codable struct: `box: [Int]` (x1,y1,x2,y2), `score`, `classId`, `className`, `text`, `predCharCount` (default 100.0, used by cascade recognizer)
- `OCRResult` — `detections: [Detection]`, `text: String`
- `HistoryItem` — Codable, stored as JSON + JPEG in `Documents/ScanHistory/`

### ONNX Models (gitignored)

Located in `KotenOCR/Models/`, downloaded via `setup.sh`:

Koten models:
- `rtmdet-s-1280x1280.onnx` (~40MB) — RTMDet detection
- `parseq-ndl-32x384-tiny-10.onnx` (~38MB) — PARSeq recognition
- `ndl.yaml` — model config (thresholds, max_detections)

NDL models:
- `deim-s-1024x1024.onnx` (~38MB) — DEIMv2 detection
- `parseq-ndl-16x256-30-tiny-192epoch-tegaki3.onnx` (~34MB) — 30-char recognition
- `parseq-ndl-16x384-50-tiny-146epoch-tegaki2.onnx` (~35MB) — 50-char recognition
- `parseq-ndl-16x768-100-tiny-165epoch-tegaki2.onnx` (~39MB) — 100-char recognition
- `ndl-deim.yaml` — DEIMv2 config (17 class names)

Shared:
- `NDLmoji.yaml` — character set definition (7141 chars)

## Localization

Two languages: Japanese (`ja.lproj/`) and English (`en.lproj/`). Use `String(localized:defaultValue:)` pattern. Both Localizable.strings files must be updated in sync.

## App Store Connect API

Credentials stored in `.env` (gitignored). API key `.p8` file at `~/.private_keys/`. JWT auth with PyJWT. Key operations documented in the blog post at `/Users/nakamura/git/zenn/content/ja/posts/appstore-connect-api-guide.md`.

## Dependencies

- **ONNX Runtime** (SPM, v1.20.0+) — ML inference
- **StoreKit 2** — In-app purchases (TipJar.storekit)
- Post-build script fixes MinimumOSVersion in onnxruntime.framework and re-signs

## Screenshot Automation

UIテスト (`KotenOCRUITests/ScreenshotTests.swift`) でiPhone・iPad両方のApp Storeスクリーンショットを自動撮影し、マーケティング画像を生成してアップロードする。

テストメソッド:
- `testCaptureOCRResult` — OCR結果、現代語訳、カメラ、設定画面を撮影
- `testDemoVideoFlow` — デモ動画用フロー（OCR結果→スクロール→翻訳→設定）

ダミー翻訳テキストは `TEST_TRANSLATION_TEXT` 環境変数で注入（`ScreenshotTests.swift` で設定）。
レビューダイアログ抑制: 起動引数 `-ocrSuccessCount 999`。
言語切替: `-testLanguage ja/en` + アプリ側 `-AppleLanguages` で日英UIを切替。

```bash
# 全自動（JA/EN撮影→マーケティング画像生成→デモ動画録画）
./scripts/capture_screenshots.sh

# アップロードも含む
./scripts/capture_screenshots.sh --upload

# マーケティング画像のみ再生成（言語別）
python3 scripts/generate_marketing_screenshots.py \
    --input-iphone DIR --input-ipad DIR --output DIR --lang ja
python3 scripts/generate_marketing_screenshots.py \
    --input-iphone DIR --input-ipad DIR --output DIR --lang en

# App Store Connectへアップロードのみ（ja/, en/ サブディレクトリ対応）
python3 scripts/upload_screenshots.py --dir screenshots/marketing
python3 scripts/upload_screenshots.py --dir screenshots/marketing --dry-run
```

### マーケティング画像の仕様

- iPhone 6.7": 1290x2796、iPad 12.9": 2048x2732（Apple必須サイズ）
- 3テーマ × 2デバイス × 2言語 = 12枚生成（`screenshots/marketing/{ja,en}/`）
- デバイスフレーム（ダークベゼル）付き、下部見切れレイアウト
- iPhone/iPadで幅・フォントサイズ等のパラメータを分離
- 英語版は英語UIスクリーンショット + 英語見出し

### デモ動画

- `xcrun simctl io recordVideo` でシミュレータ画面を録画
- JA/EN各1本（iPhone）、`/tmp/kotenocr_screenshots/videos/` に出力
- App Storeプレビュー動画として使用可能（最大30秒）

### テスト用サンプル画像

OCRテスト・スクリーンショット撮影用のサンプル古典籍画像（東京大学IIIF）:
```
https://iiif.dl.itc.u-tokyo.ac.jp/iiif/genji/TIFF/A00_6587/01/01_0004.tif/full/full/0/default.jpg
```

ローカルコピー: `KotenOCRUITests/Resources/test_koten_sample.jpg`

## Project Generation

Uses **XcodeGen** (`project.yml`). After modifying project settings, run `xcodegen generate` to regenerate `KotenOCR.xcodeproj`.
