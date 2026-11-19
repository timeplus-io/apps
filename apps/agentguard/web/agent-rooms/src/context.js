// What the Timeplus console tells a custom app UI, read from the entry URL:
//   {entry_url}?workspace=default&app_id=io.timeplus.agentguard&db=ag&theme=dark
// Nothing here asks the user for anything; a missing value falls back to a safe default.

const DB = /^[A-Za-z_][A-Za-z0-9_]*$/;
export const LOOKBACKS = [15, 30, 60, 180, 720, 1440];

/**
 * @param {string} search    location.search
 * @param {string} pathname  location.pathname, /{workspace}/apps/{app_id}/ui/{name}/...
 * @param {string|number} [savedMinutes]  look-back the viewer chose last time
 */
export function readContext(search, pathname, savedMinutes) {
  const qs = new URLSearchParams(search), seg = String(pathname || '').split('/').filter(Boolean);
  const served = seg[1] === 'apps' && seg[3] === 'ui';
  const db = qs.get('db') || '';
  const m = Math.round(Number(qs.get('minutes') || savedMinutes));
  let workspace = 'default';
  try { workspace = qs.get('workspace') || (served && decodeURIComponent(seg[0])) || 'default'; } catch { /* malformed escape in the path */ }
  return {
    workspace,
    appId: qs.get('app_id') || (served ? seg[2] : ''),
    db: DB.test(db) ? db : 'ag',
    theme: qs.get('theme') === 'light' ? 'light' : 'dark',
    minutes: m >= 1 && m <= 1440 ? m : 30
  };
}
