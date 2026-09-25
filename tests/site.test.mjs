/**
 * 紹介ページ (docs/) の公開 URL (https://kotenocr.ldas.jp) と、旧 URL からの転送設定を固定する。
 * docs/ は Vercel (Root Directory = docs) でそのまま配られる。
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const SITE = 'https://kotenocr.ldas.jp';
const read = (p) => readFileSync(new URL(`../docs/${p}`, import.meta.url), 'utf8');
const index = read('index.html');
const privacy = read('privacy-policy.html');
const attr = (html, re) => html.match(re)?.[1];

test('トップの canonical と og:url が新ホストの /', () => {
  assert.equal(attr(index, /<link rel="canonical" href="([^"]+)"/), `${SITE}/`);
  assert.equal(attr(index, /property="og:url" content="([^"]+)"/), `${SITE}/`);
});

test('og:image と twitter:image が新ホストの icon.png', () => {
  const imgs = [...index.matchAll(/(?:property="og:image"|name="twitter:image")\s+content="([^"]+)"/g)].map((m) => m[1]);
  assert.deepEqual(imgs, [`${SITE}/icon.png`, `${SITE}/icon.png`]);
});

test('プライバシーポリシーの canonical が新ホスト (App Store に登録する URL)', () => {
  assert.equal(attr(privacy, /<link rel="canonical" href="([^"]+)"/), `${SITE}/privacy-policy.html`);
});

test('robots.txt と sitemap.xml が新ホストを指す', () => {
  assert.match(read('robots.txt'), new RegExp(`^Sitemap: ${SITE}/sitemap\\.xml$`, 'm'));
  const locs = [...read('sitemap.xml').matchAll(/<loc>([^<]+)<\/loc>/g)].map((m) => m[1]);
  assert.deepEqual(locs, [`${SITE}/`, `${SITE}/privacy-policy.html`]);
});

test('vercel.json: 旧ホスト koten-ocr-ios.vercel.app の全パスを新ホストの同じパスへ恒久転送 (308)', () => {
  const cfg = JSON.parse(read('vercel.json'));
  assert.deepEqual(cfg.redirects, [
    {
      source: '/:path*',
      has: [{ type: 'host', value: 'koten-ocr-ios.vercel.app' }],
      destination: `${SITE}/:path*`,
      permanent: true,
    },
  ]);
  // 新ホストでは転送しない (条件に host が無い転送があると、新ホストでも輪になる)
  for (const r of cfg.redirects) assert.ok(r.has?.some((h) => h.type === 'host'), r.source);
});

test('docs/ に package.json を置かない (Vercel の Root Directory なので、置くとビルドが走る)', () => {
  assert.throws(() => read('package.json'), { code: 'ENOENT' });
});
