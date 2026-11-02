---
title: Android 版
eyebrow: Android
lead: Android 版の KotenOCR を作っています。Google Play での公開の前に、テストに参加していただける方を募集しています。それまでの間は、APK というファイルでも配っています。
description: KotenOCR の Android 版。Google Play のテスター募集と、APK での配布の案内。
alternate: { title: English, url: android-en.html, lang: en }
quick_links:
  - { title: テストに参加する, text: Google Play から入れる, url: "#tester", mark: "✓" }
  - { title: APK を入れる, text: "2.1.0 · Android 8 以降", url: "#apk", mark: "↓" }
---

Android 版は、iPhone 版の 2.1 と同じ機能を持っています。
読み取りは端末の中だけで行います。撮った画像を端末の外に送ることはありません。

### テストに参加する（Google Play）
{: #tester }

Google Play で一般に公開するには、12 人以上の方に 14 日間続けてテストに参加していただく必要があります。
ご協力いただけますと助かります。

1. Google グループ [KotenOCR Android テスター](https://groups.google.com/g/kotenocr-android-testers) を開き、「グループに参加」を押します。
   Android の端末で使っている Google アカウントで参加してください。
2. [テストへの参加ページ](https://play.google.com/apps/testing/com.nakamura196.koten_ocr) を開き、「テスターになる」を押します。
3. [Google Play の KotenOCR](https://play.google.com/store/apps/details?id=com.nakamura196.koten_ocr) からインストールします。

> 14 日間は、アプリを入れたままにしておいていただけますと幸いです。毎日使う必要はありません。
> 参加すると、お使いの Google アカウントのメールアドレスが、管理者（開発者）に見えます。ほかのメンバーには見えません。
> グループに投稿できるのは管理者だけです。ふだんメールが届くことはありません。
> やめるときは、テストへの参加ページで「テストから退出」を押し、グループから退会してください。
{: .point }

不具合やご意見は、Google Play のアプリのページから送るか、[GitHub の Issues](https://github.com/nakamura196/koten-ocr-android/issues) にお寄せください。

### APK を入れる
{: #apk }

Google Play を使わずに、ファイルから直接入れることもできます。

1. [GitHub の配布ページ](https://github.com/nakamura196/koten-ocr-android/releases/latest) から **KotenOCR-2.1.0.apk**（約 236MB）を、Android の端末でダウンロードします。Wi-Fi での取得をおすすめします。
2. ダウンロードしたファイルを開きます。「提供元不明のアプリ」の許可を求められたら、ブラウザ（または「ファイル」アプリ）に許可を与えます。
3. 「インストール」を押します。

- 対応: Android 8.0 以上、64 ビット（arm64）の端末
- 初回の起動時は、読み取りの準備に 20 秒ほどかかります

> APK 版は、Google Play 版とは別のアプリとして入ります。両方を入れることもできます。
> 更新は自動では届きません。新しい版は配布ページに載せます。
> Google Play 版が公開されたら、そちらへの移行をおすすめします。APK 版の読み取り履歴は引き継がれません。
{: .point }

### リンク

- [トップページ](./)（できること・読み取りの仕組み）
- [ソースコード（Android 版）](https://github.com/nakamura196/koten-ocr-android)
- [プライバシーポリシー](privacy-policy.html)
