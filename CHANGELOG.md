# Changelog / 変更履歴

## 2.1 (Unreleased)

- 切り抜き画面に「自動補正」を追加。ページの四隅を探して、斜めに撮った頁をまっすぐに直す。気に入らなければ「元に戻す」 / Added Auto-correct on the crop screen: finds the page corners and straightens a page photographed at an angle; Undo restores the original
- 結果画面に「確信度」のスライダーを追加。上げると自信のない枠から隠れる（表示だけで、読み取り結果は変わらない） / Added a Confidence slider on the result screen: raising it hides the least certain lines (display only; the results themselves are kept)
- 細い行（傍書など）の番号を読める大きさにし、重なる番号をずらして表示 / Line numbers on thin lines (such as side notes) are now legible, and overlapping numbers are moved apart
- 近代モードで、見出しなど短い行を短い行用のモデルで読むように（NDLOCR-Lite と同じ）。枠の座標と検出の線引きも NDLOCR-Lite にそろえた / Modern mode reads short lines such as headings with the short-line models, as NDLOCR-Lite does; box coordinates and the detection threshold now match NDLOCR-Lite
- 読み順: 1 つの行が細切れに検出されたとき、上から順に並ぶように / Reading order: fragments of one column are now kept top to bottom
- 白黒（16 ビット）の画像を回転すると失敗する不具合と、画像の向きの扱いを修正 / Fixed rotating 16-bit grayscale images, and image orientation handling
- 履歴の保存を確実に（書き込みの途中で終了しても壊れにくく） / History is saved more reliably (files are written atomically)
- アップデートの案内を、操作を妨げない形に / Update notices no longer block the app
- 翻訳の API キーをこの端末だけに保存（機種変更やバックアップからの復元では再入力が必要） / The translation API key is now stored on this device only (re-enter it after moving to a new device or restoring a backup)
- プライバシーマニフェストを追加し、プライバシーポリシーを実際の動作に合わせて更新 / Added a privacy manifest and updated the privacy policy to describe what the app actually does

## 2.0.1 (2026-10-30)

- 最初の説明で、撮影のほかに写真から読み込めることを案内 / The first-run guide now mentions that you can also choose a photo, not only take one
- 切り抜き画面の回転ボタンに「回転」と文字を表示 / The rotate button on the crop screen now shows a "Rotate" label

## 2.0 (2026-10-30)

- ホームに「サンプルの頁で試す」を追加。『竹取物語』・『源氏物語』（古典籍）と国立国会図書館の資料（近代）の 3 頁を選ぶとすぐに読み取る / Added "Try a sample page" on the home screen: three bundled pages (Taketori Monogatari and The Tale of Genji for Classical, an NDL document for Modern) that read straight away
- 結果画面の行番号を枠の外（縦書きは上、横書きは左）に出し、行頭の文字を隠さないように。2 桁の番号も折り返さない / Line numbers on the result screen now sit outside the box (above vertical lines, left of horizontal ones) so they no longer hide the first characters; two-digit numbers no longer wrap
- 行番号に白い縁と半透明をつけ、選んだ行の番号は濃く手前に表示。枠の線は行の太さに合わせ、小さな番号でも枠との間を空ける / Line numbers have a white rim and are slightly transparent, the selected one solid and on top; box lines follow the line thickness, and small numbers keep a clear gap from their box
- 4点補正で角を動かした直後に、ページの自動検出が遅れて終わると、動かした角が元に戻ることがある不具合を修正 / Fixed corners moved in four-corner crop sometimes snapping back when automatic page detection finished late
- 近代モードで、1行だけの見出しや図の説明（キャプション）が読み取られないことがある不具合を修正。国立国会図書館の NDLOCR-Lite と同じ行を読むように / Modern mode no longer drops one-line headings and figure captions; it now reads the same lines as NDL's NDLOCR-Lite
- 新聞のように行の多い紙面で、100 行を超えた分が読まれない不具合を修正（公式の NDL の OCR と同じく上限なし） / Pages with more than 100 lines, such as newspapers, are now read in full (no cap, as in NDL's official OCR)
- 確認画面で最後に選んだモード（古典籍／近代）を次回も選択。サンプルを試しても変わらない / The confirm screen remembers the mode you last chose; trying a sample does not change it

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
- デザインを一新：文書と読み取った文字は和紙の色・明朝体・朱で表示し、操作ボタンは iOS 26 の Liquid Glass（iOS 16〜25 では白と朱の板）に / New design: documents and recognized text use washi paper colours, Mincho type and vermilion (朱) accents; controls use Liquid Glass on iOS 26 and solid white / 朱 plates on iOS 16–25
- アプリアイコンを和紙・墨・朱の配色に変更（ダーク・色付きアイコンにも対応） / App icon recoloured to washi, ink and 朱, with dark and tinted variants
- ホームに「最近の読み取り」を最大3件表示。押すとその結果を開く / Home shows up to three recent scans; tap one to open it
- 読み取り中に朱の光が進み具合に合わせて動き、見つかった行が読む順に現れる。完了時に朱印を押す動きと触覚 / While reading, a vermilion beam follows the progress and found lines appear in reading order; a seal stamp and haptic mark completion
- 初回の説明で、写本の頁に実際の読み取り結果（枠と文字）を読む順に再生。撮影ボタンと範囲の角に一度だけの吹き出し（設定から再表示可） / The first-run introduction replays a real recognition result (boxes and text) on a manuscript page; one-time hints on the shutter and the crop corner (can be shown again from Settings)
- 履歴が空のときの絵、文字が見つからなかったときのコツ、カメラが使えないときの案内画面を追加 / Added an empty-history illustration, tips when no text is found, and a camera-unavailable screen
- 範囲選択の後は「古典籍／近代」を選んで「読み取る」を押す形に変更。コピーは右下のボタンから、完了は上に短く表示 / After cropping, choose Classical or Modern and tap Read; Copy is a floating button with a short “Copied” toast
- 「視差効果を減らす」設定では動きをフェードに置き換え。文字の大きさ設定（アクセシビリティサイズを含む）に合わせて配置を調整 / Reduce Motion replaces movement with cross-fades; layouts adapt to Dynamic Type including accessibility sizes
- 結果画面に「枠を直す」を追加：枠の選択・移動・大きさ変更・削除・追加・分割・結合ができ、変えた枠だけを「再認識」して読む順を並べ直す。元に戻す／キャンセル対応、履歴にも保存 / Added Edit Boxes on the result screen: select, move, resize, delete, add, split and merge line boxes, then Re-read only the changed boxes and re-run reading order; with Undo and Cancel, saved to history
- 2枚目以降の解析で落ちることがある不具合を修正。解析のたびにメモリ使用量が増え続けていた（文字検出を毎回別のスレッドで実行し、スレッドごとに約100MBの作業領域が残っていた）。撮影・写真の画像は長辺4096pxに縮小して取り込み、新しい撮影の前に前の画像を解放 / Fixed a crash when analysing the 2nd or later image: memory grew with every analysis (line detection ran on a different thread each time and each thread kept ~100 MB of scratch memory). Photos are now taken in at most 4096 px on the long side, and the previous page's images are released before a new capture

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
