// Tests for the console-context helper. The bundle ships a copy of skill/assets/tp-context.js;
// the tests run against that copy and check it has not drifted from the source.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { parseContext, mergeContext, matchLocale, watchContext } from '../../web/agent-rooms/vendor/tp-context.js';

const PATH = '/acme/apps/io.example.app/ui/live/';
const ORIGIN = 'https://console.example';

test('the vendored copy is the helper from skill/assets', () => {
  const read = p => readFileSync(new URL(p, import.meta.url), 'utf8');
  assert.equal(read('../../web/agent-rooms/vendor/tp-context.js'), read('../../../../skill/assets/tp-context.js'),
    'run `make vendor-context` in apps/agentguard');
});

test('parseContext reads the five query parameters', () => {
  assert.deepEqual(parseContext('?workspace=acme&app_id=io.example.app&db=my_app&theme=dark&locale=zh-CN', PATH),
    { workspace: 'acme', appId: 'io.example.app', db: 'my_app', theme: 'dark', locale: 'zh-CN' });
});
test('parseContext falls back to the serve path, then to the defaults', () => {
  assert.deepEqual(parseContext('', PATH), { workspace: 'acme', appId: 'io.example.app', db: '', theme: 'light', locale: 'en-US' });
  assert.deepEqual(parseContext('', '/index.html', { db: 'my_app', theme: 'dark' }),
    { workspace: 'default', appId: '', db: 'my_app', theme: 'dark', locale: 'en-US' });
  assert.equal(parseContext('', '/%E0%A4%A/apps/a/ui/b/').workspace, 'default');
});
test('parseContext rejects a db that is not an identifier, an unknown theme and a malformed locale', () => {
  const c = parseContext('?db=x;DROP&theme=neon&locale=<b>', PATH, { db: 'my_app' });
  assert.deepEqual([c.db, c.theme, c.locale], ['my_app', 'light', 'en-US']);
  assert.equal(parseContext('?locale=fr-FR', PATH).locale, 'fr-FR'); // well-formed tags pass; the page picks its strings
});

test('mergeContext applies a context message field by field', () => {
  const ctx = parseContext('?db=my_app&theme=dark', PATH);
  assert.deepEqual(mergeContext(ctx, { type: 'timeplus:context', version: 1, workspace: 'acme', app_id: 'io.example.app', db: 'my_app', theme: 'light', locale: 'zh-CN' }),
    { ...ctx, theme: 'light', locale: 'zh-CN' });
  assert.deepEqual(mergeContext(ctx, { type: 'timeplus:context' }), ctx);
  assert.deepEqual(mergeContext(ctx, { type: 'timeplus:context', theme: 'neon', locale: 7, db: 'x y', future: true }), ctx);
});
test('mergeContext ignores anything that is not a context message', () => {
  const ctx = parseContext('', PATH);
  for (const data of [null, 'timeplus:context', 42, {}, { type: 'timeplus:context-request' }, { type: 'other', theme: 'dark' }])
    assert.equal(mergeContext(ctx, data), null);
});

test('matchLocale picks an exact match, then the language, then the first', () => {
  const have = ['en-US', 'zh-CN'];
  assert.equal(matchLocale('zh-CN', have), 'zh-CN');
  assert.equal(matchLocale('zh-TW', have), 'zh-CN');
  assert.equal(matchLocale('EN-us', have), 'en-US');
  assert.equal(matchLocale('fr-FR', have), 'en-US');
  assert.equal(matchLocale(undefined, have), 'en-US');
});

/** A stand-in for the page's window, framed by `parent` (or top-level when omitted). */
function fakeWindow(search, parent) {
  const handlers = [], win = {
    location: { search, pathname: PATH, origin: ORIGIN },
    document: { documentElement: { dataset: {}, lang: '' } },
    addEventListener: (type, fn) => { assert.equal(type, 'message'); handlers.push(fn); },
    deliver: ev => handlers.forEach(fn => fn(ev))
  };
  win.parent = parent || win;
  return win;
}
const fakeParent = () => { const p = { sent: [], postMessage: (data, origin) => p.sent.push([data, origin]) }; return p; };
const MSG = { type: 'timeplus:context', version: 1, theme: 'light', locale: 'zh-CN' };

test('watchContext applies the URL to <html>, listens, then asks the console', () => {
  const parent = fakeParent(), win = fakeWindow('?db=my_app&theme=dark&locale=zh-CN', parent);
  const w = watchContext(win);
  assert.equal(w.get().theme, 'dark');
  assert.deepEqual([win.document.documentElement.dataset.theme, win.document.documentElement.lang], ['dark', 'zh-CN']);
  assert.deepEqual(parent.sent, [[{ type: 'timeplus:context-request' }, ORIGIN]]);
});
test('watchContext applies a message from the console without a reload and tells listeners', () => {
  const parent = fakeParent(), win = fakeWindow('?db=my_app&theme=dark', parent), w = watchContext(win), calls = [];
  const stop = w.onChange((next, prev) => calls.push([next.theme, next.locale, prev.theme, prev.locale]));
  win.deliver({ origin: ORIGIN, source: parent, data: MSG });
  assert.deepEqual(calls, [['light', 'zh-CN', 'dark', 'en-US']]);
  assert.deepEqual([w.get().theme, w.get().db], ['light', 'my_app']);
  assert.deepEqual([win.document.documentElement.dataset.theme, win.document.documentElement.lang], ['light', 'zh-CN']);
  win.deliver({ origin: ORIGIN, source: parent, data: MSG }); // a repeat still fires; the page compares
  assert.equal(calls.length, 2);
  stop();
  win.deliver({ origin: ORIGIN, source: parent, data: { ...MSG, theme: 'dark' } });
  assert.equal(calls.length, 2);
  assert.equal(w.get().theme, 'dark');
});
test('watchContext ignores another origin, another window and another message type', () => {
  const parent = fakeParent(), win = fakeWindow('?theme=dark', parent), w = watchContext(win);
  let n = 0; w.onChange(() => n++);
  win.deliver({ origin: 'https://evil.example', source: parent, data: MSG });
  win.deliver({ origin: ORIGIN, source: fakeParent(), data: MSG });
  win.deliver({ origin: ORIGIN, source: parent, data: { type: 'something-else', theme: 'light' } });
  assert.equal(n, 0);
  assert.equal(w.get().theme, 'dark');
});
test('watchContext keeps the URL values when the page is opened directly in a tab', () => {
  const win = fakeWindow('?theme=dark&locale=zh-CN');
  win.postMessage = data => win.deliver({ origin: ORIGIN, source: win, data }); // its own request comes back to it
  const w = watchContext(win);
  let n = 0; w.onChange(() => n++);
  win.postMessage({ type: 'timeplus:context-request' });
  assert.equal(n, 0);
  assert.deepEqual([w.get().theme, w.get().locale], ['dark', 'zh-CN']);
});
test('watchContext leaves <html> alone when asked', () => {
  const win = fakeWindow('?theme=dark', fakeParent());
  watchContext(win, { applyToDocument: false });
  assert.deepEqual(win.document.documentElement, { dataset: {}, lang: '' });
});
