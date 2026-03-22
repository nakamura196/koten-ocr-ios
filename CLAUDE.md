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

専用スクリプト `scripts/record_demo_video.sh` でシミュレータ画面を自動録画 → ffmpegでトリミング。
App Storeプレビュー動画（最大30秒）として使用可能。出力先: `/tmp/kotenocr_videos/`

```bash
# 古典籍 OCR のみ（デフォルト）
./scripts/record_demo_video.sh

# 近代 OCR のみ（校異源氏物語、クロップ→モード選択フロー）
./scripts/record_demo_video.sh --mode picker

# 古典籍 + 近代 OCR を1本の動画に（推奨）
./scripts/record_demo_video.sh --mode combined

# 日英両方
./scripts/record_demo_video.sh --mode combined --lang all

# トリミング調整（デフォルト: 先頭10.5秒カット＝スプラッシュ残し、30秒に制限）
./scripts/record_demo_video.sh --mode combined --trim-start 10.5 --trim-duration 30

# トリミングなし（生データ確認用）
./scripts/record_demo_video.sh --mode combined --no-trim
```

テストメソッド（`KotenOCRUITests/ScreenshotTests.swift`）:
- `testDemoVideoFlow` — 古典籍 auto-load → OCR結果 → スクロール → 翻訳
- `testDemoVideoPickerFlow` — 校異源氏物語 → クロップ → 近代OCR選択 → OCR結果
- `testDemoVideoCombined` — 古典籍OCR → 翻訳 → 校異源氏物語クロップ → 近代OCR（1本に統合）

自動化の仕組み:
- `TEST_IMAGE_PATH` — 起動時に自動ロードするテスト画像パス
- `TEST_SHOW_CROP` — `YES` で自動ロード時にクロップ画面を経由
- `TEST_SECOND_IMAGE_PATH` — カメラに戻った際に2枚目を自動ロード（combined用）
- `TEST_TRANSLATION_TEXT` — ダミー翻訳テキストの注入
- 録画後 ffmpeg で冒頭（ホーム画面+スプラッシュ）と末尾を自動トリミング

### デモ動画の配布先と形式

| 配布先 | ファイル | 形式 | フレーム |
|--------|---------|------|---------|
| GitHub README | `screenshots/demo_v130.gif` | GIF (10fps, 360px) | iPhoneデバイスフレーム付き |
| zenn記事・docs | `screenshots/demo_v130.mp4` | MP4 | フレームなし |
| App Store Connect | `/tmp/kotenocr_videos/` | MP4 (H.264) | フレームなし |

- GIF（README用）はデバイスフレーム（ダークベゼル+角丸）を付けるとモダンな見栄え
- 動画（zenn/docs/App Store用）はフレームなし。プレーヤー再生時に余白が出るため
- App Store Connectへのアップロードは `scripts/upload_preview.py`（PREPARE_FOR_SUBMISSION状態が必要）

### デモ動画の更新手順

```bash
# 1. 録画（古典籍+近代の統合動画）
./scripts/record_demo_video.sh --mode combined

# 2. GIF変換（デバイスフレーム付き、Python Pillow使用）
#    extract frames → add_rounded_corners → add_device_frame → encode GIF
#    ffmpegでパレット最適化: max_colors=128, dither=bayer
#    出力: screenshots/demo_v130.gif

# 3. MP4をコピー
cp /tmp/kotenocr_videos/demo_ja_combined_iphone.mp4 screenshots/demo_v130.mp4

# 4. commit & push
git add screenshots/demo_v130.gif screenshots/demo_v130.mp4
git commit -m "Update demo video and GIF"
git push

# 5. App Store Connect（レビュー外の時のみ）
python3 scripts/upload_preview.py --video /tmp/kotenocr_videos/demo_ja_combined_iphone.mp4 --lang ja
```

### テスト用サンプル画像

古典籍（くずし字）モード用（東京大学IIIF）:
```
https://iiif.dl.itc.u-tokyo.ac.jp/iiif/genji/TIFF/A00_6587/01/01_0004.tif/full/full/0/default.jpg
```
ローカルコピー: `KotenOCRUITests/Resources/test_koten_sample.jpg`

近代（活字・手書き）モード用 — 校異源氏物語（国立国会図書館デジタルコレクション）:
ローカルコピー: `KotenOCRUITests/Resources/test_ndl_sample.jpg`

## バージョンアップ時のTODOリスト

新バージョンをリリースする際のチェックリスト。漏れ防止のため、上から順に実施する。

### 1. コード変更
- [ ] `project.yml` の `MARKETING_VERSION` と `CURRENT_PROJECT_VERSION` を更新
- [ ] `CHANGELOG.md` に変更内容を追記
- [ ] `xcodegen generate` でXcodeプロジェクトを再生成

### 2. ドキュメント更新
- [ ] `docs/index.html` の更新履歴セクションに新バージョンを追加
- [ ] `docs/appstore-metadata.md` の必要箇所を更新（説明文変更がある場合）
- [ ] `README.md` の更新（機能追加がある場合）
- [ ] `CLAUDE.md` の更新（アーキテクチャ変更がある場合）

### 3. デモ動画・スクリーンショット（UI変更がある場合）
- [ ] `./scripts/record_demo_video.sh --mode combined` でデモ動画を再録画
- [ ] GIF変換（デバイスフレーム付き）→ `screenshots/demo_v130.gif`
- [ ] MP4コピー → `screenshots/demo_v130.mp4`
- [ ] zennの記事の動画も更新（`static/videos/posts/kotenocr/`）

### 4. ビルド＆提出（API経由）

詳細手順は `/Users/nakamura/git/zenn/content/ja/posts/ios-app-update-submission-api-guide.md` を参照。

```bash
# 4.1 Info.plistのバージョンも更新（project.ymlだけでは不十分）
# KotenOCR/Info.plist の CFBundleShortVersionString, CFBundleVersion

# 4.2 クリーンアーカイブ（キャッシュ防止のため clean 必須）
xcodegen generate
xcodebuild clean -project KotenOCR.xcodeproj -scheme KotenOCR -quiet
xcodebuild -project KotenOCR.xcodeproj -scheme KotenOCR -configuration Release \
  -archivePath /tmp/KotenOCR.xcarchive archive -allowProvisioningUpdates

# 4.3 エクスポート
xcodebuild -exportArchive -archivePath /tmp/KotenOCR.xcarchive \
  -exportOptionsPlist scripts/ExportOptions.plist -exportPath /tmp/KotenOCR_export \
  -allowProvisioningUpdates

# 4.4 アップロード
xcrun altool --upload-app --file /tmp/KotenOCR_export/KotenOCR.ipa --type ios \
  --apiKey "$(grep APP_STORE_API_KEY .env | cut -d= -f2)" \
  --apiIssuer "$(grep APP_STORE_API_ISSUER .env | cut -d= -f2)"

# 4.5 API経由で審査提出（Python）
# - 新バージョン作成（READY_FOR_SALEの場合）
# - ビルド関連付け（build → appStoreVersion）
# - whatsNew（リリースノート）を日英両方設定（必須）
# - reviewSubmissions → reviewSubmissionItems → submitted=True
```

- [ ] `KotenOCR/Info.plist` のバージョンを更新
- [ ] クリーンアーカイブ＆エクスポート＆アップロード
- [ ] API経由でバージョン作成・ビルド関連付け・whatsNew設定・審査提出
- [ ] プレビュー動画のアップロード（`scripts/upload_preview.py`、審査提出前に実行すること）

### App Storeプレビュー動画の仕様

スクリーンショットとは解像度が異なるので注意。

| デバイス | 解像度（縦） | 解像度（横） |
|---------|------------|------------|
| iPhone 6.7" | **886 x 1920** | 1920 x 886 |
| iPad 13" | 1200 x 1600 | 1600 x 1200 |

- コーデック: H.264（High Profile Level 4.0）、30fps以下、プログレッシブ
- 音声: **ステレオ音声トラック必須**（無音でもAAC 256kbps ステレオトラックが必要）
- 長さ: 15〜30秒
- ファイル: MP4/MOV、500MB以下、`-movflags +faststart`

```bash
# シミュレータ録画 → App Store用に変換
ffmpeg -y -f lavfi -i anullsrc=r=44100:cl=stereo \
  -i /tmp/kotenocr_videos/demo_ja_combined_iphone.mp4 \
  -vf "scale=886:1920" -c:v libx264 -preset fast -crf 18 -r 30 \
  -c:a aac -b:a 256k -shortest -movflags +faststart \
  /tmp/kotenocr_videos/demo_ja_appstore.mp4

# アップロード（PREPARE_FOR_SUBMISSION状態で、審査提出前に）
python3 scripts/upload_preview.py --video /tmp/kotenocr_videos/demo_ja_appstore.mp4 --lang ja
```

### 5. Git
- [ ] 変更をcommit & push
- [ ] zennリポジトリもcommit & push（記事更新がある場合）

## Project Generation

Uses **XcodeGen** (`project.yml`). After modifying project settings, run `xcodegen generate` to regenerate `KotenOCR.xcodeproj`.
