# Changelog / 変更履歴

## Unreleased

- 起動時にホーム画面を表示（撮影する／写真から選ぶ／履歴／設定）。いきなりカメラが開かないように変更 / Added a home (start) screen on launch with Take Photo, Choose from Photos, History and Settings, instead of opening straight into the camera
- カメラ画面にホームへ戻るボタンを追加 / Added a Home button on the camera screen
- 翻訳が別の履歴に保存されることがある不具合を修正 / Fixed translations sometimes being saved to the wrong history item
- 結果画面で編集したテキストが履歴に保存されない不具合を修正 / Fixed manual text edits not being saved to history
- 回転後に「スキップ」すると回転が失われる不具合、切り抜き枠の移動が加速する不具合を修正 / Fixed rotation being lost on Skip in the crop screen, and the crop box accelerating while dragged
- カメラの撮影ボタンの二重タップ防止、撮影失敗時のエラー表示、カメラ未許可時の案内と設定ボタンを追加 / Camera: prevent double capture, show an error when capture fails, and show guidance with an Open Settings button when access is denied
- OCRエラーを日本語/英語のわかりやすい文言と「撮り直す」ボタンで表示 / OCR errors now show a readable localized message with a Retake button
- 履歴一覧をサムネイル化して高速化。削除前に確認を表示 / Faster history list using small thumbnails; added delete confirmation
- VoiceOver: 履歴行に日付と先頭の文を追加、結果画面にテキスト編集ボタンを追加、拡大リセットにラベルを追加 / Accessibility: history rows include date and first line, visible edit button for recognized text, label for the reset-zoom button
- 書き出しファイル名に日時を付与（例: KotenOCR_20261029_2154.txt） / Export file names now include date and time
- 不足していたローカライズ文字列と権限説明（InfoPlist.strings）を追加 / Added missing localized strings and localized permission descriptions
- カメラ画面に「書類スキャン」を追加（VisionKit）。ページの端を自動検出し、斜めに撮っても補正。最後に使った方式を次回も使用 / Added Scan document on the camera screen (VisionKit): detects page edges and corrects perspective; remembers the last used capture mode
- カメラに傾きガイドを追加（水平器と「資料と平行に構えてください」）。設定でオフにできます / Added a tilt guide on the camera (level indicator and a "hold parallel" hint), switchable in Settings
- 切り抜き画面に4点補正モードを追加。四隅を個別に動かして台形ゆがみを補正 / Added a four-corner crop mode that corrects keystone distortion
- 撮影した資料の小さな傾き（±10°以内）を自動で補正してから行を検出するように。傾いたページで枠が隣の行と重なり、隣の行の文字が混ざる問題を軽減 / Automatic small-angle deskew (within ±10°) before line detection, reducing overlapping boxes and text leaking from adjacent lines on tilted pages
- 設定に「傾きを自動補正」を追加（既定ON） / Added "Auto-correct tilt" setting (on by default)
- OCR結果・履歴・書き出しの画像は、補正後の（OCRを実行した）画像に統一 / Result, history and export now use the deskewed image that OCR actually ran on
- 古典籍モードで、斜めから撮ったページの行ごとの傾きに対応。傾いた行は行に沿って切り出して読むため、隣の行の文字が混ざりにくい。同じ行を二重に検出した場合の重複行と、「□□□□」だけの行も表示しない / Classical mode now handles lines that lean by different amounts (pages shot at an angle): leaning lines are read from crops that follow the line, so neighbouring text no longer leaks in. Duplicate lines from detecting the same column twice, and lines that read only as "□□□□", are dropped

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
