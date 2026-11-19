// Side panel: session status and the history of the selected object. Reads only from the Store session.
import { META, LEGEND, iconURL } from './icons.js';

const esc = s => String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
export const k = n => (n / 1000).toFixed(n < 10000 ? 1 : 0) + 'k';
export function age(ms) { const s = Math.max(0, Math.round(ms / 1000)); return s < 90 ? s + 's ago' : s < 5400 ? Math.round(s / 60) + 'm ago' : Math.round(s / 3600) + 'h ago'; }
const dot = c => `<span class="dot" style="background:${c}"></span>`;

export function renderPanel(room, sel, narr, now = Date.now()) {
  const s = room.ses, pct = Math.min(100, s.ctx / s.ctxLimit * 100), kind = sel.kind, est = s.ctxReal ? '' : '≈ ';
  const dotc = room.state === 'Error' ? '#D12D50' : room.state === 'Idle' ? '#7D7B82' : '#D53F8C';
  const session = `<div><div class="eyebrow">Session</div><h2>${esc(s.name)}</h2></div>
  <div class="grid"><span class="k">Agent</span><span class="v"><span class="badge">${esc(s.badge)}</span> ${esc(s.typeName)}${s.model ? ' · ' + esc(s.model) : ''}</span>
  <span class="k">State</span><span class="v">${dot(dotc)} ${room.actor.cur && room.actor.cur.go ? esc(narr(room)) : room.state + (room.detail ? ' · ' + esc(room.detail) : '')}</span>
  <span class="k">Context</span><span class="v">${est}${k(s.ctx)} / ${k(s.ctxLimit)} · ${Math.round(pct)}%</span>
  <span class="k">Tool calls</span><span class="v">${s.calls}</span></div>
  <div class="gauge"><i style="width:${pct}%;background:${pct >= 80 ? '#D53F8C' : '#7D7B82'}"></i></div>
  ${s.ctxReal ? '' : '<div class="hint">Context size is estimated from payload sizes until token metrics arrive for this session.</div>'}
  <div><div class="k">Current task</div><div class="v">${esc(s.task || 'None yet')}</div></div>
  <div><div class="k">Latest user prompt</div><div class="box">${esc(s.prompt || 'Waiting for a call')}</div></div>`;
  if (kind === 'room') return session + `<div class="hr"></div><div class="hint">Each object carries an icon sign. Hover for its name; click to open its history here.</div><div>${LEGEND.map(q => `<div class="row" style="align-items:center"><img src="${iconURL(q)}" width="20" height="20" alt=""><span style="font-weight:600">${META[q][0]}</span></div>`).join('')}</div>`;

  let h = '';
  if (kind === 'card') {
    const c = sel.card;
    h = `<div><div class="eyebrow">Context card</div><h2>${esc(c.label)}</h2></div><div class="grid"><span class="k">Source</span><span class="v" style="display:flex;align-items:center;gap:6px"><img src="${iconURL(c.type)}" width="18" height="18" alt="">${META[c.type][0]}</span><span class="k">Result</span><span class="v">${dot(c.ok ? '#B5B4B8' : '#D12D50')} ${c.ok ? 'Succeeded' : 'Failed'}</span><span class="k">Context cost</span><span class="v">${c.unknownSize ? 'not reported' : (c.real ? '' : '≈ ') + c.tok.toLocaleString() + ' tokens'}</span><span class="k">Added</span><span class="v">${age(now - c.ts)}</span></div><div class="hint">The thickness of a card on the bench is its token cost${c.real ? '' : ', estimated from the size of the tool input and result'}. The icon on top is where it came from.</div>`;
  } else {
    const m = META[kind]; h = `<div><div class="eyebrow">Selected</div><h2>${m[0]}</h2><div class="hint">${m[1]}</div></div>`;
    if (kind === 'bench') {
      const hs = s.hist.slice(-36), mx = Math.max(...hs.map(x => x.v), 1);
      h += `<div><div class="k">Context size over time</div>${hs.length ? `<div class="spark">${hs.map((x, i) => `<i class="${i === hs.length - 1 ? 'last' : ''}" style="height:${x.v / mx * 100}%"></i>`).join('')}</div>` : '<div class="hint">No token metrics for this session yet.</div>'}</div>
      <div><div class="k">${s.cards.length} cards on the bench</div>${s.cards.slice(-9).reverse().map(c => `<div class="row">${dot(c.ok ? '#B5B4B8' : '#D12D50')}<span>${esc(c.label)}</span><span class="k">${c.unknownSize ? '—' : k(c.tok)}</span></div>`).join('')}</div>`;
    } else if (kind === 'board') h += `<div><div class="k">System prompt</div><div class="box">Not reported by ${esc(s.typeName)}. AgentGuard does not receive the system prompt text for this agent.</div></div><div><div class="k">Task in progress</div><div class="box">${esc(s.task || 'None yet')}</div></div>${s.tasks.size ? `<div><div class="k">Task list</div>${[...s.tasks.values()].map(t => `<div class="row">${dot(t.done ? '#7D7B82' : '#D53F8C')}<span>${esc(t.subject)}</span><span class="k">${t.done ? 'done' : 'open'}</span></div>`).join('')}</div>` : ''}`;
    else if (kind === 'agent') { const subs = [...s.subs.values()].filter(x => !x.ended); h += `<div class="grid"><span class="k">Type</span><span class="v">${esc(s.typeName)}</span><span class="k">Model</span><span class="v">${esc(s.model || 'not reported yet')}</span><span class="k">Agent id</span><span class="v">${esc(s.agentId || '—')}</span><span class="k">Sub-agents</span><span class="v">${subs.length ? subs.map(x => esc(x.name)).join(', ') : 'none'}</span><span class="k">Failures</span><span class="v">${s.failures}</span></div>`; }
    else if (kind === 'skill') { const used = [...s.skillsUsed.entries()]; h += `<div><div class="k">Skills used in this session</div>${used.length ? used.map(([n, c]) => `<div class="row"><img src="${iconURL('skill')}" width="16" height="16" alt=""><span style="font-weight:600">${esc(n)}</span><span class="k">×${c}</span></div>`).join('') : '<div class="hint">None yet.</div>'}</div>${s.skillsAvailable.size ? `<div class="hint">${s.skillsAvailable.size} skills listed as available in the prompt.</div>` : ''}`; }
    else if (kind === 'memory') { const ops = Object.entries(s.memoryOps); h += `<div><div class="k">Memory operations</div>${ops.length ? `<div class="grid">${ops.map(([o, c]) => `<span class="k">${esc(o[0].toUpperCase() + o.slice(1))}</span><span class="v">${c}</span>`).join('')}</div>` : '<div class="hint">None yet.</div>'}</div>`; }
    if (kind !== 'bench' && kind !== 'agent') {
      const ls = s.log.filter(x => x.kind === kind || kind === 'subbench' && x.sub), fails = ls.filter(x => !x.ok).length, bins = Array(12).fill(0);
      ls.forEach(x => { const b = 11 - Math.floor((now - x.ts) / 8000); if (b >= 0 && b < 12) bins[b]++; }); const mx = Math.max(...bins, 1);
      h += `<div class="grid"><span class="k">Events</span><span class="v">${ls.length}</span><span class="k">Failures</span><span class="v">${fails}</span><span class="k">Tokens added</span><span class="v">≈ ${k(ls.reduce((a, x) => a + x.tok, 0))}</span></div>
      <div><div class="k">Activity, last 96 s</div><div class="spark">${bins.map((x, i) => `<i class="${i === 11 ? 'last' : ''}" style="height:${x / mx * 100}%"></i>`).join('')}</div></div>
      <div><div class="k">History</div>${ls.length ? ls.slice(-8).reverse().map(x => `<div class="row">${dot(x.ok ? '#B5B4B8' : '#D12D50')}<span>${esc(x.label)}</span><span class="k">${age(now - x.ts)}</span></div>`).join('') : '<div class="hint">Nothing yet in this session.</div>'}</div>`;
    }
  }
  return h + '<div class="hr"></div>' + session;
}
