// Minimal Timeplus REST API query client for a custom app UI (SSE over fetch).
// The page is served on the console's origin, so requests carry the viewer's session cookie:
// no credentials are asked for, stored or sent in a header.
import { SSEParser, RowDecoder } from './sse.js';

export const queryURL = cfg => `/${encodeURIComponent(cfg.workspace || 'default')}/api/v1beta2/queries`;
export const SIGNED_OUT = 'Your Timeplus session has ended. Sign in again in the console, then reload this page.';

/**
 * Run one query and stream its rows. Resolves when the server closes the stream
 * (bounded query finished, or a streaming query was cancelled / dropped).
 */
export async function runQuery(cfg, sql, { onRows, onOpen, signal } = {}) {
  const res = await fetch(queryURL(cfg), {
    method: 'POST', signal, credentials: 'same-origin',
    // An ended session is answered with 401 or, under password login, a redirect to the logout page.
    // 'manual' keeps the browser from following that redirect on the page's behalf.
    redirect: 'manual',
    headers: { 'Content-Type': 'application/json', Accept: 'text/event-stream' },
    body: JSON.stringify({ sql })
  });
  if (res.status === 401 || res.type === 'opaqueredirect' || res.redirected) { const err = new Error(SIGNED_OUT); err.status = 401; err.signedOut = true; throw err; }
  if (!res.ok) {
    let msg = res.status + ' ' + res.statusText;
    try { const j = await res.json(); if (j && j.message) msg = j.message; } catch { /* keep status text */ }
    const err = new Error(msg); err.status = res.status; throw err;
  }
  onOpen && onOpen(); // accepted: a query with no rows yet is still live
  const reader = res.body.getReader(), td = new TextDecoder(), sse = new SSEParser(), dec = new RowDecoder();
  for (;;) {
    const { value, done } = await reader.read(); if (done) break;
    for (const ev of sse.feed(td.decode(value, { stream: true }))) { const rows = dec.push(ev); if (rows.length && onRows) onRows(rows); }
    if (dec.status === 'failed') throw new Error(dec.message || 'Query failed');
  }
}

/**
 * Keep a streaming query alive: on a dropped connection, re-run it from the last
 * timestamp seen. `makeSQL(sinceMs)` builds the SQL; rows must carry a `ts` column (epoch ms).
 * An ended session ('signedout') and SQL errors (4xx, 'error') are not retried. Returns a stop() function.
 */
export function follow(cfg, makeSQL, { onRows, onStatus } = {}) {
  const ac = new AbortController(); let last = 0, tries = 0;
  (async () => {
    while (!ac.signal.aborted) {
      try {
        onStatus && onStatus('connecting');
        await runQuery(cfg, makeSQL(last || undefined), { signal: ac.signal, onOpen: () => { tries = 0; onStatus && onStatus('live'); }, onRows: rows => {
          for (const r of rows) if (r.ts > last) last = Number(r.ts);
          onRows(rows);
        } });
      } catch (e) {
        if (ac.signal.aborted) return;
        if (e.status >= 400 && e.status < 500) { onStatus && onStatus(e.signedOut ? 'signedout' : 'error', e.message); return; }
        onStatus && onStatus('retrying', e.message);
      }
      if (ac.signal.aborted) return;
      await new Promise(r => setTimeout(r, Math.min(15000, 1500 * ++tries)));
    }
  })();
  return () => ac.abort();
}
