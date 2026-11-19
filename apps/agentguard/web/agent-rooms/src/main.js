// App wiring: context from the console -> five streaming queries -> Store -> rooms + side panel.
import * as THREE from '../vendor/three.module.min.js';
import { Store } from './store.js';
import { follow } from './timeplus.js';
import { eventsSQL, metricsSQL, hooksSQL, skillsSQL, memorySQL } from './queries.js';
import { createScene, SLOTS } from './scene.js';
import { renderPanel } from './panel.js';
import { setIconInk } from './icons.js';
import { readContext, LOOKBACKS } from './context.js';

const $ = s => document.querySelector(s);
const esc = s => String(s).replace(/[&<>]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]));

// ---------- context from the console ----------
const saved = (() => { try { return localStorage.getItem('agentRooms.minutes'); } catch { return null; } })();
const cfg = readContext(location.search, location.pathname, saved);
document.documentElement.dataset.theme = cfg.theme;
setIconInk(cfg.theme === 'light' ? '#120F1A' : '#F7F6F6');

const store = new Store();
let sel = { slot: -1, kind: 'room' }, stops = [], status = { events: 'connecting', metrics: 'connecting', hooks: 'connecting', skills: 'connecting', memory: 'connecting' }, errMsg = '';
const scene = createScene(THREE, { stage: $('#stage'), canvas: $('#cv'), overlay: $('#ov'), store,
  onSelect: (s, focused) => { sel = s; drawTabs(); panel(); if (!focused) $('#panel').scrollTop = 0; } });

// ---------- header ----------
function drawTabs() {
  const tabs = $('#tabs'); tabs.innerHTML = '';
  [['All rooms', -1], ...scene.rooms.map((r, i) => r && [r.ses.name, i]).filter(Boolean)].forEach(([n, i]) => {
    const b = document.createElement('button'); b.textContent = n; if (i === scene.focus) b.className = 'on';
    b.onclick = () => { scene.setFocus(i); sel = { slot: i, kind: 'room' }; drawTabs(); panel(); }; tabs.appendChild(b);
  });
}
$('#pause').onclick = e => { scene.paused = !scene.paused; e.target.textContent = scene.paused ? 'Play' : 'Pause'; };
function drawStatus() {
  const v = Object.values(status), st = v.includes('signedout') ? 'signedout' : v.includes('error') ? 'error' : v.every(x => x === 'live') ? 'live' : v.includes('retrying') ? 'retrying' : 'connecting';
  const txt = { live: 'Live', signedout: 'Signed out', error: 'Query failed', retrying: 'Reconnecting', connecting: 'Connecting' }[st], bad = st === 'error' || st === 'signedout';
  $('#conn').innerHTML = `<span class="dot" style="background:${st === 'live' ? '#D53F8C' : bad ? '#D12D50' : '#7D7B82'}"></span>${txt}`;
  $('#conn').title = `workspace ${cfg.workspace} · database ${cfg.db}`;
  $('#err').hidden = !bad; $('#errmsg').textContent = bad ? (st === 'error' ? 'Query failed: ' : '') + errMsg : '';
  scene.emptyText = bad ? $('#errmsg').textContent : `No agent sessions in the last ${lookLabel(cfg.minutes)}. Waiting for events on ${cfg.db}.agentguard_cim_event.`;
}

// ---------- side panel ----------
function panel() {
  const room = scene.rooms[sel.slot];
  if (!room) {
    const n = store.top(99).length;
    $('#panel').innerHTML = `<div><div class="eyebrow">Sessions</div><h2>${n ? n + ' active' : 'None yet'}</h2></div><div class="hint">${n ? 'Click a room, or a tab above, to follow its agent.' : esc(scene.emptyText)}</div>` +
      store.top(SLOTS).map(s => `<div class="row"><span class="badge">${esc(s.badge)}</span><span>${esc(s.name)}</span><span class="k">${s.calls} calls</span></div>`).join('');
    return;
  }
  $('#panel').innerHTML = renderPanel(room, sel, scene.narr);
}
setInterval(panel, 500);

// ---------- data flow ----------
// Rows from the five queries are buffered briefly and applied in timestamp order, because
// backfill batches are not globally ordered and the queries deliver independently.
let buf = [], lastRow = 0, firstRow = 0;
const add = src => rows => { for (const r of rows) buf.push([Number(r.ts) || 0, src, r]); lastRow = Date.now(); if (!firstRow) firstRow = lastRow; };
let settled = false;
function drain() {
  if (!settled) { if (!lastRow || (Date.now() - lastRow < 400 && Date.now() - firstRow < 3000)) return; settled = true; } // take the whole backfill in one sorted pass
  if (buf.length) {
    const b = buf; buf = []; b.sort((x, y) => x[0] - y[0] || x[1] - y[1]);
    for (const [, src, r] of b) [store.event, store.hook, store.metric, store.skill, store.memory][src].call(store, r);
  }
  store.flush();
  reconcile();
}
setInterval(drain, 200);

/** Keep the most recently active sessions in rooms. A session keeps its slot while it stays in the top set. */
function reconcile() {
  const want = store.top(SLOTS), have = new Set(scene.rooms.filter(Boolean).map(r => r.ses));
  let changed = false;
  scene.rooms.forEach((r, i) => { if (r && !want.includes(r.ses)) { scene.detach(i); if (sel.slot === i) sel = { slot: -1, kind: 'room' }; changed = true; } });
  for (const s of want) if (!have.has(s)) {
    const i = scene.rooms.findIndex(r => !r); if (i < 0) break; scene.attach(s, i); changed = true;
    // Follow a newly started session when the one being watched has ended.
    const cur = scene.rooms[scene.focus]; if (cur && cur.ses.ended && !s.ended && sel.kind === 'room') { scene.setFocus(i); sel = { slot: i, kind: 'room' }; }
  }
  if (changed) {
    if (scene.focus < 0 && sel.slot < 0 && scene.rooms.filter(Boolean).length === 1) { const i = scene.rooms.findIndex(Boolean); scene.setFocus(i); sel = { slot: i, kind: 'room' }; }
    drawTabs(); panel();
  }
}

function connect() {
  stops.forEach(f => f()); stops = []; errMsg = '';
  scene.rooms.forEach((r, i) => r && scene.detach(i)); store.sessions.clear(); store.orphans.clear(); buf = []; settled = false; lastRow = firstRow = 0; sel = { slot: -1, kind: 'room' }; drawTabs(); panel();
  for (const key in status) status[key] = 'connecting';
  const st = key => (s, msg) => { status[key] = s; if (msg) errMsg = msg; drawStatus(); };
  try {
    stops = [
      follow(cfg, t => eventsSQL(cfg.db, cfg.minutes, t), { onRows: add(0), onStatus: st('events') }),
      follow(cfg, t => hooksSQL(cfg.db, cfg.minutes, t), { onRows: add(1), onStatus: st('hooks') }),
      follow(cfg, t => metricsSQL(cfg.db, cfg.minutes, t), { onRows: add(2), onStatus: st('metrics') }),
      follow(cfg, t => skillsSQL(cfg.db, cfg.minutes, t), { onRows: add(3), onStatus: st('skills') }),
      follow(cfg, t => memorySQL(cfg.db, cfg.minutes, t), { onRows: add(4), onStatus: st('memory') })
    ];
  } catch (e) { errMsg = e.message; status.events = 'error'; drawStatus(); }
}

// ---------- look-back window ----------
function lookLabel(m) { return m % 60 ? m + ' minutes' : m === 60 ? 'hour' : m / 60 + ' hours'; }
const look = $('#minutes');
if (!LOOKBACKS.includes(cfg.minutes)) look.add(new Option(lookLabel(cfg.minutes), cfg.minutes), 0);
look.value = String(cfg.minutes);
look.onchange = () => { cfg.minutes = Number(look.value); try { localStorage.setItem('agentRooms.minutes', look.value); } catch { /* storage unavailable */ } connect(); };
$('#retry').onclick = connect;

drawTabs(); drawStatus(); connect();
