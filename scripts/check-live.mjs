#!/usr/bin/env node
/**
 * 本番 (kotenocr.ldas.jp) と旧 URL の転送を、実際に HTTP で叩いて確かめる。
 * マージ (= Vercel の本番配布) と独自ドメインの設定後に手元で実行する: npm run test:live
 *
 * 見ること:
 *   1. 新ホストのトップとプライバシーポリシーが 200 で、canonical がそれぞれ自分を指す
 *   2. トップが読む相対の資産 (icon・画像・動画・favicon) と robots.txt・sitemap.xml が 200
 *   3. 存在しないパスが 404、http は https へ転送
 *   4. 旧 koten-ocr-ios.vercel.app/<path>?<query> が同じパス・クエリのまま新ホストへ 308
 *      (App Store のマーケティング URL とプライバシーポリシー URL はこの旧ホストで登録されている)
 */
const NEW = 'https://kotenocr.ldas.jp';
const OLD = 'https://koten-ocr-ios.vercel.app';

const errors = [];
let passed = 0;
const ok = (cond, msg) => (cond ? passed++ : errors.push(msg));
const get = (url, opts = {}) => fetch(url, { redirect: 'manual', ...opts });

// 1, 2
let assets = [];
for (const page of ['/', '/privacy-policy.html']) {
  const r = await get(NEW + page);
  ok(r.status === 200, `${NEW}${page} → ${r.status} (200 のはず)`);
  const html = await r.text();
  const canonical = html.match(/<link rel="canonical" href="([^"]+)"/)?.[1];
  ok(canonical === NEW + page, `${page} の canonical が ${canonical}`);
  if (page === '/') assets = [...html.matchAll(/\s(?:href|src)="([^"#:]+)"/g)].map((m) => m[1]);
}
ok(assets.length > 0, 'トップから相対の資産参照が見つからない');
for (const path of new Set([...assets.filter((a) => a !== 'privacy-policy.html'), 'robots.txt', 'sitemap.xml'])) {
  const r = await get(`${NEW}/${path}`, { method: 'HEAD' });
  ok(r.status === 200, `${NEW}/${path} → ${r.status}`);
}

// 3
{
  const r = await get(NEW + '/no-such-page/');
  ok(r.status === 404, `存在しないページが ${r.status} (404 のはず)`);
  const h = await get('http://kotenocr.ldas.jp/?q=1');
  const loc = h.headers.get('location');
  ok([301, 308].includes(h.status) && loc === `${NEW}/?q=1`, `http → ${h.status} ${loc} (${NEW}/?q=1 のはず)`);
}

// 4
for (const path of ['/', '/privacy-policy.html', '/?q=1', '/icon.png']) {
  const r = await get(OLD + path);
  const loc = r.headers.get('location');
  ok(r.status === 308 && loc === NEW + path, `${OLD}${path} → ${r.status} ${loc} (308 ${NEW + path} のはず)`);
}

if (errors.length) {
  console.error(`NG: ${errors.length} 件 (OK ${passed} 件)`);
  for (const e of errors) console.error('  ' + e);
  process.exit(1);
}
console.log(`OK: ${passed} 件`);
