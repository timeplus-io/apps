// tp-context.js: what the Timeplus console tells a custom app UI.
//
// Copy this file into the bundle (for example vendor/tp-context.js) and import it by
// relative path. It has no dependencies and loads nothing.
//
//   import { getContext, onContextChange } from './vendor/tp-context.js';
//   const ctx = getContext({ db: 'my_app' });   // { workspace, appId, db, theme, locale }
//   onContextChange((next, prev) => { if (next.locale !== prev.locale) translate(next.locale); });
//
// At load the values come from the entry URL:
//   {entry_url}?workspace=default&app_id=io.example.app&db=my_app&theme=dark&locale=zh-CN
// After load the console posts { type: 'timeplus:context', version: 1, workspace, app_id,
// db, theme, locale } to the frame: once it has loaded, on every theme or language change,
// and in answer to { type: 'timeplus:context-request' }.
//
// `locale` and the message exist from Timeplus Web (the console) 3.5.4, shipped with
// Timeplus app server 3.5.3. An older console sends neither: `locale` is then 'en-US' and
// the change callback never fires. Opened directly in a tab the page has no console
// around it and keeps the URL values.
//
// By default the helper keeps <html data-theme> and <html lang> current, so a page styled
// with CSS variables under :root[data-theme=...] follows a theme change with no code.

const DB = /^[A-Za-z_][A-Za-z0-9_]*$/;
// Shape of a BCP 47 tag (en, en-US, zh-Hans-CN). Not a registry lookup.
const LOCALE = /^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$/;

const FALLBACK = { workspace: 'default', appId: '', db: '', theme: 'light', locale: 'en-US' };

const str = v => (typeof v === 'string' ? v : '');
const pickTheme = (v, d) => (v === 'light' || v === 'dark' ? v : d);
const pickLocale = (v, d) => (LOCALE.test(str(v)) ? v : d);
const pickDb = (v, d) => (DB.test(str(v)) ? v : d);

/**
 * Context from the entry URL. Pure: takes the strings, touches nothing.
 * A missing or invalid value falls back to `defaults`, then to
 * { workspace: 'default', appId: '', db: '', theme: 'light', locale: 'en-US' }.
 * `db` goes into SQL text, so it is accepted only when it is a plain identifier.
 *
 * @param {string} search    location.search
 * @param {string} pathname  location.pathname, /{workspace}/apps/{app_id}/ui/{name}/...
 * @param {{workspace?: string, appId?: string, db?: string, theme?: string, locale?: string}} [defaults]
 */
export function parseContext(search, pathname, defaults) {
  const d = { ...FALLBACK, ...defaults };
  const qs = new URLSearchParams(search || '');
  const seg = String(pathname || '').split('/').filter(Boolean);
  const served = seg[1] === 'apps' && seg[3] === 'ui';
  let fromPath = '';
  try { fromPath = served ? decodeURIComponent(seg[0]) : ''; } catch { /* malformed escape in the path */ }
  return {
    workspace: qs.get('workspace') || fromPath || d.workspace,
    appId: qs.get('app_id') || (served ? seg[2] : '') || d.appId,
    db: pickDb(qs.get('db'), d.db),
    theme: pickTheme(qs.get('theme'), d.theme),
    locale: pickLocale(qs.get('locale'), d.locale),
  };
}

/**
 * Apply a message from the console to a context. Pure.
 * Returns the next context, or null when `data` is not a `timeplus:context` message.
 * Every field is optional; a missing or invalid one keeps its current value, and
 * unknown fields are ignored.
 */
export function mergeContext(ctx, data) {
  if (!data || typeof data !== 'object' || data.type !== 'timeplus:context') return null;
  return {
    workspace: str(data.workspace) || ctx.workspace,
    appId: str(data.app_id) || ctx.appId,
    db: pickDb(data.db, ctx.db),
    theme: pickTheme(data.theme, ctx.theme),
    locale: pickLocale(data.locale, ctx.locale),
  };
}

/**
 * The first of `supported` that fits `locale`: an exact match, else the same language
 * (zh-TW fits zh-CN), else supported[0]. For choosing a string table.
 */
export function matchLocale(locale, supported) {
  const want = str(locale).toLowerCase(), lang = want.split('-')[0];
  return supported.find(s => s.toLowerCase() === want)
    || supported.find(s => s.toLowerCase().split('-')[0] === lang)
    || supported[0];
}

/**
 * Follow the console's context in the window `win`. `getContext` and `onContextChange`
 * below share one of these for the page's own window; call this directly only in tests.
 *
 * @param {Window} win
 * @param {object} [defaults]  as for parseContext, plus `applyToDocument: false` to leave
 *                             <html data-theme> and <html lang> alone
 */
export function watchContext(win, defaults) {
  const { applyToDocument = true, ...d } = defaults || {};
  const listeners = new Set();
  let ctx = parseContext(win.location.search, win.location.pathname, d);

  const apply = () => {
    if (!applyToDocument) return;
    const root = win.document.documentElement;
    root.dataset.theme = ctx.theme;
    root.lang = ctx.locale;
  };
  apply();

  // Only the console that framed this page may send the context: same origin, and the
  // parent window. Opened directly in a tab the page is its own parent and nothing else
  // on the origin posts to it.
  win.addEventListener('message', ev => {
    if (ev.origin !== win.location.origin || ev.source !== win.parent) return;
    const next = mergeContext(ctx, ev.data);
    if (!next) return;
    const prev = ctx;
    ctx = next;
    apply();
    for (const fn of [...listeners]) fn(ctx, prev);
  });
  // Ask for the current values, after the listener exists: the console may have posted its
  // first message before this module ran. Sent without testing for a parent frame first.
  // Opened directly in a tab the request goes to the page itself and is ignored; an older
  // console ignores it too.
  try { win.parent.postMessage({ type: 'timeplus:context-request' }, win.location.origin); } catch { /* no parent to ask */ }

  return {
    /** The current context. A new object after every change; do not mutate it. */
    get: () => ctx,
    /** Call `fn(next, prev)` for each context message from the console. Returns a function that stops it. */
    onChange(fn) { listeners.add(fn); return () => listeners.delete(fn); },
  };
}

let shared;
const sharedWatch = defaults => shared || (shared = watchContext(window, defaults));

/**
 * The current context: { workspace, appId, db, theme, locale }.
 * The first call reads the entry URL, sets <html data-theme> and <html lang>, and starts
 * listening to the console. `defaults` is used by that first call only.
 */
export function getContext(defaults) { return sharedWatch(defaults).get(); }

/**
 * Call `fn(next, prev)` for each `timeplus:context` message from the console, including
 * ones that repeat the current values (the console sends one when the frame has loaded).
 * Compare `next` with `prev` before doing expensive work. Returns a function that stops it.
 */
export function onContextChange(fn) { return sharedWatch().onChange(fn); }
