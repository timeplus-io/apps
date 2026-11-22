// The page's own setting: how far back sessions are loaded from. Workspace, database, theme
// and locale come from the console through ../vendor/tp-context.js.

export const LOOKBACKS = [15, 30, 60, 180, 720, 1440];

/**
 * Look-back in minutes: `?minutes=` in the URL, then the viewer's last choice, then 30.
 * @param {string} search  location.search
 * @param {string|number} [saved]  look-back the viewer chose last time
 */
export function readMinutes(search, saved) {
  const m = Math.round(Number(new URLSearchParams(search).get('minutes') || saved));
  return m >= 1 && m <= 1440 ? m : 30;
}
