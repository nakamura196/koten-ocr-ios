# Changelog / 変更履歴

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
