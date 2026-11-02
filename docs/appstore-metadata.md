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

App Store の説明文は、版の提出のときにしか変えられない（審査が要る）。2.1 は 2026-11-01 に出たが、
説明文は 1.x の時代のまま（古典籍モードだけ・「すべての処理をデバイス上で完結」）。次の版の提出で入れる。

```
古典籍のくずし字や、明治以降の活字・手書きの資料を、撮るだけで文字にするOCRアプリです。国立国会図書館が公開しているOCRのモデルを、iPhone・iPadの中で動かします。無料です。

【2つの読み方】
・古典籍：江戸期までの版本・写本のくずし字（変体仮名を含む）。7,000字以上に対応（NDL古典籍OCR-Lite）
・近代：明治以降の活字の印刷物と、手書きの文書（NDLOCR-Lite）

【できること】
・撮る・選ぶ：カメラで撮るほか、写真から選べます。書類スキャンで、ページの端を見つけて取り込むこともできます
・まっすぐに直す：斜めに撮ったページは「自動補正」で四隅を見つけて直します。小さな傾きは読む前に自動で直します
・枠を直す：読み取った行の枠を動かす・分ける・まとめる・足すことができ、変えた行だけを読み直します
・確信度：スライダーを上げると、自信のない行から隠れます（表示だけで、結果は変わりません）
・現代語訳：古文を現代の日本語か英語に訳します。一般向け・学生向け・研究者向けを選べます
・履歴と書き出し：読んだ結果は端末の中に残ります。テキスト・TXT・PDFで書き出せます
・サンプルで試す：『竹取物語』『源氏物語』と国立国会図書館の資料の3頁を、撮らずにすぐ試せます

【使い方】
1. 撮影する、または写真から選ぶ
2. 読む範囲を決める（「自動補正」で斜めの頁を直せます）
3. 「古典籍」か「近代」を選んで「読み取る」
4. 結果を確かめ、コピー・共有・書き出し

【送るもの・送らないもの】
・文字の読み取りは端末の中だけで行います。インターネットは要りません
・画像は、どの機能でも端末の外に送りません
・現代語訳は、iOS 26以降でApple Intelligenceが使える端末では、端末の中のAIで行います
・設定でクラウドのAPI（OpenAI・OpenRouterなど）を選んだときだけ、読み取ったテキストが、選んだ事業者に送られます
・アカウントは不要です。開発者が利用者の情報を集めることはありません
くわしくはプライバシーポリシー（https://kotenocr.ldas.jp/privacy-policy.html）をご覧ください。

【ライセンス】
・OCRモデル: NDL古典籍OCR-Lite / NDLOCR-Lite（国立国会図書館, CC BY 4.0）
・推論エンジン: ONNX Runtime（Microsoft, MIT License）

紹介ページ・使い方の動画: https://kotenocr.ldas.jp
ソースコード: https://github.com/nakamura196/koten-ocr-ios
```

## 説明文（英語）

```
KotenOCR turns photos of classical Japanese books written in cursive script (kuzushiji), and of modern printed or handwritten documents from the Meiji era onward, into text. It runs the OCR models published by the National Diet Library of Japan on your iPhone or iPad. Free.

Two reading modes
• Classical: kuzushiji in woodblock-printed books and manuscripts up to the Edo period, including hentaigana. 7,000+ characters (NDL Koten OCR-Lite)
• Modern: printed and handwritten documents from the Meiji era onward (NDLOCR-Lite)

What you can do
• Capture or choose: take a photo, pick one from Photos, or use Scan document to find the page edges
• Straighten: Auto-correct finds the corners of a page shot at an angle and straightens it. Small tilts are corrected automatically before reading
• Edit boxes: move, split, merge or add line boxes, and re-read only the lines you changed
• Confidence: raise the slider to hide the least certain lines (display only; the results are kept)
• Translation: translate classical Japanese into modern Japanese or English, for general readers, students or researchers
• History and export: results stay on your device. Export as text, TXT or PDF
• Try a sample: three bundled pages (Taketori Monogatari, The Tale of Genji, and an NDL document) to try without taking a photo

How to use
1. Take a photo or choose one from Photos
2. Set the area to read (Auto-correct straightens angled pages)
3. Choose Classical or Modern and tap Read
4. Check the result, then copy, share or export

What is sent, and what is not
• OCR runs only on your device. No internet connection is needed
• Images are never sent off the device by any feature
• On iOS 26 or later with Apple Intelligence, translation uses the on-device model
• Only if you choose a cloud API in Settings (OpenAI, OpenRouter, etc.) is the recognized text sent to the provider you chose
• No account needed. The developer does not collect your information
Details: https://kotenocr.ldas.jp/privacy-policy.html

Licenses
• OCR models: NDL Koten OCR-Lite / NDLOCR-Lite (National Diet Library, CC BY 4.0)
• Inference engine: ONNX Runtime (Microsoft, MIT License)

Website and tutorial videos: https://kotenocr.ldas.jp/en.html
Source code: https://github.com/nakamura196/koten-ocr-ios
```

## キーワード（日本語、最大100文字）

アプリ名・サブタイトルにある語（OCR・古典籍・くずし字）は検索に効くので、キーワードからは外して枠を空ける。

```
文字認識,古文書,和本,写本,版本,変体仮名,翻刻,現代語訳,国立国会図書館,NDL,活字,近代,明治,オフライン
```

## キーワード（英語、最大100文字）

```
kuzushiji,Japanese,classical,manuscript,woodblock,hentaigana,transcription,NDL,translation,offline
```

## プロモーションテキスト（170文字以内。審査なしでいつでも変えられる）

```
2.1 で、斜めに撮った頁をまっすぐに直す「自動補正」と、自信のない行を隠す「確信度」を加えました。読み取りは端末の中だけで行い、画像はどこへも送りません。
```

```
2.1: Auto-correct straightens pages shot at an angle, and a Confidence slider hides the least certain lines. OCR runs only on your device; images are never sent anywhere.
```

## サポートURL（ユーザーの問い合わせ先）

```
https://github.com/nakamura196/koten-ocr-ios/issues
```

## マーケティングURL（アプリ紹介ページ）

2026-11-01、販売中の 2.1 に対して API で変えようとしたが 409 で断られた（マーケティング URL・プライバシーポリシー URL とも）。
変えられるのは、新しい版を作って提出するとき。プロモーションテキストは販売中でも変えられた（同じ送信に URL を混ぜると一緒に断られる）。
英語のロケールは `https://kotenocr.ldas.jp/en.html` にする。

```
https://kotenocr.ldas.jp
```

## プライバシーポリシーURL

App Store 提出時に公開URLが必要。docs/ を GitHub Pages（Jekyll、guide-theme）で配っている（2026-11-01 に Vercel から移した）:
```
https://kotenocr.ldas.jp/privacy-policy.html
```
2026-09 時点の App Store の登録は旧 `https://koten-ocr-ios.vercel.app/privacy-policy.html`。旧ホストは Vercel のプロジェクトを残してあり、docs/vercel.json（Vercel に最後に配った版）で同じパスへ 308 転送するので、そのままでも開ける。次の版の提出時に新 URL へ書き換える。

## App Storeプレビュー動画

| 項目 | 仕様 |
|------|------|
| 形式 | MP4 (H.264) |
| 最大長 | 30秒 |
| デバイス | iPhone 6.7" (iPhone 17 Pro Max) |
| 言語 | 日本語 / 英語 |

デモ動画は `scripts/record_demo_video.sh` で自動生成。古典籍OCRと近代OCRの両モードを紹介。

<video src="demo_v130.mp4" controls muted playsinline width="300"></video>

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
