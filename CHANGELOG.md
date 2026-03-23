# Changelog / 変更履歴

## 1.3.2 (2026-03-24)

- メモリ使用量を大幅削減。起動時に選択中のモードのみロード（遅延ロード） / Reduced memory usage: lazy model loading (only selected mode at startup)
- DEIMDetector前処理を最適化（ピークメモリ63MB→2.4MB） / Optimized DEIMDetector preprocessing (peak memory 63MB → 2.4MB)
- 並列認識タスクを最大4バッチに制限（メモリスパイク防止） / Limited parallel recognition to 4-batch (prevents memory spikes)
- メモリ警告時に未使用モデルを自動解放 / Auto-release unused models on memory warning
- MetricKitによるクラッシュ診断収集を追加 / Added MetricKit crash diagnostics
- クラッシュリスクの追加修正（IoU境界チェック、ゼロ除算防止、force unwrap除去） / Additional crash fixes (IoU bounds check, division-by-zero guard, force unwrap removal)

## 1.3.1 (2026-03-23)

- 近代OCRの検出精度を改善。NMS（IoU=0.2）を追加し重複検出を除去 / Improved Modern OCR detection accuracy by adding NMS (IoU=0.2) to remove duplicate detections
- 近代OCRでline_*クラスのみをOCR認識対象に変更（本家ndlocr-liteと同じ挙動） / Filter to line_* classes only for OCR recognition (matching ndlocr-lite behavior)
- 検出パラメータを本家と統一（scoreThreshold=0.2, maxDetections=100） / Aligned detection parameters with upstream (scoreThreshold=0.2, maxDetections=100)

## 1.3.0 (2026-03-22)

- NDLOCR-Lite（近代活字OCR）に対応。古典籍と近代の2つのOCRモードを切り替えて使用可能 / Added NDLOCR-Lite (modern printed text OCR). Switch between Classical and Modern OCR modes
- DEIMv2検出器とカスケードPARSeq認識器を追加 / Added DEIMv2 detector and cascade PARSeq recognizer (30/50/100 char models)
- 確認画面で「古典籍 OCR」「近代 OCR」をワンタップで選択 / One-tap OCR mode selection on confirm screen
- OCR結果から「戻る」で確認画面に戻り、別モデルで再実行可能 / Back from result returns to confirm screen for easy model comparison
- 認識処理の並列化（古典籍1.4x、近代6.7x高速化） / Parallel recognition (1.4x for Classical, 6.7x for Modern)
- スプラッシュ画面を追加 / Added splash screen with app icon and tagline
- フィードバック送信機能を追加 / Added feedback email with device info
- クラッシュリスクの修正 / Fixed crash risks (safe array access, removed force unwraps)

## 1.2.2 (2026-03-19)

- App Storeマーケティング画像を更新 / Updated App Store marketing screenshots (device frames, JA/EN)
- スクリーンショット自動撮影・生成パイプラインを追加 / Added screenshot automation pipeline
- force unwrapの修正 / Fixed force unwraps in ReadingOrder, CameraView
- 空catchブロックにエラーログ追加 / Added error logging to empty catch blocks
- ローカリゼーションを統一 / Standardized localization to `String(localized:)` pattern

## 1.2.1 (2026-03-14)

- チップ（Tip Jar）機能を追加 / Added Tip Jar (in-app tips via StoreKit 2)

## 1.2.0 (2026-03-13)

- 現代語訳機能を追加（ローカルAI / クラウドAPI） / Added modern translation (local AI / cloud API)
- トリミング確認画面を追加 / Added crop confirmation screen
- カメラ保存オプションを追加 / Added camera save option

## 1.1.0 (2026-03-10)

- カメラ権限フローの改善 / Improved camera permission flow
- 設定画面にカメラ権限管理を追加 / Added camera permission management to settings
- ユニットテストを追加 / Added unit tests

## 1.0 (2026-03-04)

- 初回リリース / Initial release
- NDL古典籍OCR-Liteモデルによるくずし字OCR / Kuzushiji OCR using NDL Koten OCR-Lite models
- カメラ撮影 / フォトライブラリからのOCR / Camera capture and photo library OCR
- 認識結果のテキスト編集・エクスポート / Text editing and export (TXT/PDF)
- スキャン履歴 / Scan history
- ダーク/ライトテーマ / Dark/Light theme
- 日本語/英語対応 / Japanese/English support
