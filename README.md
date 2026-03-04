# KotenOCR

古典籍・くずし字をAIで読み取るiOS OCRアプリ。

国立国会図書館の [NDL古典籍OCR-Lite](https://github.com/ndl-lab/ndlkotenocr-lite) モデルを搭載し、すべての処理をデバイス上で完結します。インターネット接続は不要です。

## 機能

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

## 要件

- iOS 16.0+
- Xcode 15.0+
- Swift 5.9

## セットアップ

```bash
# リポジトリをクローン
git clone https://github.com/nakamura196/koten-ocr-ios.git
cd koten-ocr-ios

# ONNXモデルをダウンロード（約80MB）
./setup.sh

# Xcodeプロジェクトを生成
xcodegen generate

# Xcodeで開く
open KotenOCR.xcodeproj
```

### ONNXモデル

以下のモデルを `KotenOCR/Models/` に配置する必要があります（`.gitignore` で除外済み）：

| モデル | ファイル名 | サイズ |
|--------|-----------|--------|
| テキスト検出（RTMDet-S） | `rtmdet-s-1280x1280.onnx` | ~40MB |
| 文字認識（PaRSEQ-NDL） | `parseq-ndl-32x384-tiny-10.onnx` | ~38MB |

## プロジェクト構成

```
KotenOCR/
├── KotenOCRApp.swift          # エントリポイント
├── Theme/
│   └── AppTheme.swift         # テーマ管理
├── Views/
│   ├── ContentView.swift      # メイン画面
│   ├── CameraView.swift       # カメラ（フラッシュ・フォーカス）
│   ├── ResultOverlayView.swift # 結果表示（編集・エクスポート）
│   ├── OnboardingView.swift   # オンボーディング
│   ├── SettingsView.swift     # 設定
│   ├── HistoryListView.swift  # 履歴一覧
│   ├── TipJarView.swift       # 投げ銭
│   └── TranslationSettingsView.swift # 現代語訳設定
├── OCR/
│   ├── OCREngine.swift        # OCRパイプライン
│   ├── RTMDetector.swift      # テキスト検出
│   ├── PARSEQRecognizer.swift # 文字認識
│   └── ReadingOrder.swift     # 読み順序（xy-cut）
├── Export/
│   └── ExportManager.swift    # TXT/PDFエクスポート
├── History/
│   ├── HistoryItem.swift      # 履歴データモデル
│   └── HistoryManager.swift   # 履歴の保存/読込/削除
├── Store/
│   ├── KeychainHelper.swift   # Keychain読み書きヘルパー
│   └── TipJarManager.swift    # StoreKit 2購入管理
├── Translation/
│   └── TranslationService.swift # 現代語訳（ローカルAI / クラウドAPI、actor）
├── Models/                    # ONNXモデル（gitignore）
├── en.lproj/Localizable.strings
└── ja.lproj/Localizable.strings
```

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

### 依存ライブラリ
- **ONNX Runtime** — [MIT License](https://github.com/microsoft/onnxruntime/blob/main/LICENSE) （Microsoft）
