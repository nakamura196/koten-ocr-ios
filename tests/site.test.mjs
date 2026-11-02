/**
 * 紹介サイト (https://kotenocr.ldas.jp) の公開 URL と、旧 URL からの転送設定を固定する。
 * docs/ は GitHub Pages (Jekyll、guide-theme) で組み立てて配る。組み立てた結果 (_site/) を見る。
 * 組み立て先は環境変数 SITE_DIR (既定は _site/)。
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const SITE = 'https://kotenocr.ldas.jp';
const OUT = resolve(process.env.SITE_DIR || new URL('../_site/', import.meta.url).pathname);
const built = (p) => readFileSync(`${OUT}/${p}`, 'utf8');
const src = (p) => readFileSync(new URL(`../docs/${p}`, import.meta.url), 'utf8');
const attr = (html, re) => html.match(re)?.[1];

test('組み立てたサイトがある', () => {
  assert.ok(existsSync(`${OUT}/index.html`), `${OUT}/index.html が無い（先に docs/ を Jekyll で組み立てる）`);
});

test('トップの canonical と og:url が新ホストの /', () => {
  const index = built('index.html');
  assert.equal(attr(index, /<link rel="canonical" href="([^"]+)"/), `${SITE}/`);
  assert.equal(attr(index, /property="og:url" content="([^"]+)"/), `${SITE}/`);
});

test('og:image が日英それぞれの OGP 画像', () => {
  assert.equal(attr(built('index.html'), /property="og:image" content="([^"]+)"/), `${SITE}/assets/ogp/ogp-ja.png`);
  assert.equal(attr(built('en.html'), /property="og:image" content="([^"]+)"/), `${SITE}/assets/ogp/ogp-en.png`);
});

test('プライバシーポリシーが privacy-policy.html にあり、canonical が新ホスト (App Store に登録する URL)', () => {
  assert.equal(attr(built('privacy-policy.html'), /<link rel="canonical" href="([^"]+)"/), `${SITE}/privacy-policy.html`);
});

test('更新履歴の最新の版が CHANGELOG.md の最新の (日付のある) 版と同じ', () => {
  const log = readFileSync(new URL('../CHANGELOG.md', import.meta.url), 'utf8');
  const latest = log.match(/^## (\S+) \(\d{4}-\d{2}-\d{2}\)/m)?.[1];
  assert.ok(latest, 'CHANGELOG.md に日付のある版が無い');
  assert.match(src('changelog.md'), new RegExp(`^### ${latest.replace('.', '\\.')}（`, 'm'),
    'docs/changelog.md が古い。python3 scripts/docs/make_changelog.py を走らせる');
  assert.match(src('index.md'), new RegExp(`最新版は ${latest.replace('.', '\\.')}（`), 'docs/index.md の「最新版は」が古い');
  assert.match(src('en.md'), new RegExp(`latest version is ${latest.replace('.', '\\.')} \\(`), 'docs/en.md の "latest version" が古い');
});

test('robots.txt と sitemap.xml が新ホストを指す', () => {
  assert.match(built('robots.txt'), new RegExp(`^Sitemap: ${SITE}/sitemap\\.xml$`, 'm'));
  const locs = [...built('sitemap.xml').matchAll(/<loc>([^<]+)<\/loc>/g)].map((m) => m[1]);
  assert.ok(locs.includes(`${SITE}/`) && locs.includes(`${SITE}/privacy-policy.html`), locs.join(' '));
});

test('リポジトリの中の資料は公開しない', () => {
  for (const p of ['appstore-metadata.html', 'appstore-metadata.md', 'vercel.json']) {
    assert.ok(!existsSync(`${OUT}/${p}`), `${p} が組み立て結果に入っている`);
  }
});

test('vercel.json: 旧ホスト koten-ocr-ios.vercel.app の全パスを新ホストの同じパスへ恒久転送 (308)', () => {
  // 2026-11-01 にサイトを GitHub Pages へ移した。旧ホストの転送のためだけに Vercel のプロジェクトを残している。
  const cfg = JSON.parse(src('vercel.json'));
  assert.deepEqual(cfg.redirects, [
    {
      // /:path* はトップ (/) に当たらず、旧トップだけ 200 のまま残った (2026-09-25 に実測)。(.*) で空も含める
      source: '/:rest(.*)',
      has: [{ type: 'host', value: 'koten-ocr-ios.vercel.app' }],
      destination: `${SITE}/:rest`,
      permanent: true,
    },
  ]);
  for (const r of cfg.redirects) assert.ok(r.has?.some((h) => h.type === 'host'), r.source);
});
