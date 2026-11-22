// Session model: turns rows from the three AgentGuard queries into per-session state
// (what the side panel shows) and a queue of scene items (what the robot acts out).
//
// The conversation with the user runs both ways. In: a prompt, or the answer to a question.
// Out: what the agent says when its turn ends. That is a reply, or a question when it ends in
// one or comes through an ask-the-user tool; the session is then `waitingUser` until the user
// answers. An assistant message that turns out to be followed by more tool calls in the same
// turn was a progress update, not a reply.
// No rendering and no timers here, so it can be unit tested with plain rows.
import { toolKind, toolLabel, agentInfo, estTokens, sessionName, isAskTool, isQuestion } from './mapping.js';

const short = (s, n) => { s = String(s || '').replace(/\s+/g, ' ').trim(); return s.length > n ? s.slice(0, n - 1) + '…' : s; };
const MAX_LOG = 400, MAX_CARDS = 200, MAX_HIST = 120;

export class Store {
  constructor() { this.sessions = new Map(); this.orphans = new Map(); this.seq = 0; }

  session(id, row = {}) {
    let s = this.sessions.get(id);
    if (!s) {
      const [badge, typeName] = agentInfo(row.agent_type);
      s = { id, agentType: row.agent_type || '', badge, typeName, agentId: '', model: '', cwd: '', name: sessionName(id),
        startedTs: 0, lastTs: 0, ended: false, active: false, awaiting: false,
        prompt: '', reply: '', waitingUser: null, lastSay: null, task: '', calls: 0, failures: 0, log: [], cards: [], hist: [],
        ctx: 0, ctxReal: false, ctxLimit: 200000, mainModel: '', pending: null,
        open: new Map(), byTs: new Map(), pendingEnrich: new Map(), enriched: new Set(), tasks: new Map(), skillsUsed: new Map(), skillsAvailable: new Set(), memoryOps: {}, seen: new Set(), promptTs: 0, subs: new Map(), subSpans: [], queue: [], attached: false };
      this.sessions.set(id, s);
    }
    if (row.agent_type && !s.agentType) { s.agentType = row.agent_type; [s.badge, s.typeName] = agentInfo(row.agent_type); }
    if (row.agent_id && !s.agentId) s.agentId = row.agent_id;
    if (row.cwd && !s.cwd) s.cwd = row.cwd;
    if (row.model) s.model = row.model;
    s.name = sessionName(id, s.cwd, s.agentId);
    return s;
  }

  /** Sessions that have done something, most recently active first. */
  top(n) { return [...this.sessions.values()].filter(s => s.active).sort((a, b) => b.lastTs - a.lastTs).slice(0, n); }

  /** Start queueing scene items for a session; open calls are replayed so the robot picks them up. */
  attach(s, now = Date.now()) {
    s.attached = true; s.queue = [];
    for (const sub of s.subs.values()) { sub.queue = []; if (!sub.ended && !(sub.call && sub.call.done) && !sub.call) s.queue.push({ t: 'sub', sub }); }
    for (const c of s.open.values()) if (now - c.ts < 600000) (c.subId && s.subs.get(c.subId) ? s.subs.get(c.subId).queue : s.queue).push(c.ask ? { t: 'ask', text: c.label, call: c, resume: true } : { t: 'call', call: c });
    if (s.waitingUser && !s.waitingUser.call) s.queue.push({ t: 'ask', text: s.waitingUser.text, wait: s.waitingUser, resume: true }); // already blocked on the user: go and hold the line
  }
  detach(s) { s.attached = false; s.queue = []; for (const sub of s.subs.values()) sub.queue = []; }

  /** True when nothing is expected next: the robot should go and sleep. */
  resting(s, now = Date.now()) { return s.open.size === 0 && (s.ended || !s.awaiting || now - s.lastTs > 120000); }

  /**
   * The last thing the agent said turned out not to end its turn: it was a progress update.
   * If the robot has not acted it out yet, the queued item becomes a note and its reply card goes.
   */
  demote(s) {
    const it = s.lastSay; s.lastSay = null; if (!it || it.call) return;
    if (s.waitingUser === it.wait) s.waitingUser = null;
    if (it.taken) return; // already walked to the phone with it: leave the history as acted
    it.t = 'note'; it.entry.kind = 'note'; delete it.entry.dir; it.entry.tok = 0;
    const i = s.cards.indexOf(it.card); if (i >= 0) { s.cards.splice(i, 1); if (!s.ctxReal) s.ctx = s.cards.reduce((a, x) => a + x.tok, 0); }
    it.card = null; s.reply = it.prevReply;
  }

  // ---- lifecycle events (agentguard_cim_event) ----
  ingestEvents(rows) { for (const r of rows) this.event(r); }
  event(r) {
    if (!r.session_id) return;
    const s = this.session(r.session_id, r), ts = Number(r.ts) || 0;
    if (ts > s.lastTs) s.lastTs = ts;
    switch (r.event_type) {
      case 'session_start':
        if (r.sub_id) this.sub(s, r.sub_id, r.sub_name, ts);
        else { if (!s.startedTs) s.startedTs = ts; s.ended = false; if (r.source === 'compact') this.compacted(s, ts); } // Claude Code restarts the session after compacting
        break;
      case 'session_end':
        s.ended = true; s.awaiting = false; s.waitingUser = null; s.lastSay = null; this.closeOpen(s, ts);
        if (s.attached) s.queue.push({ t: 'end' });
        break;
      case 'user_input': {
        const text = String(r.user_message || '');
        if (ts === s.promptTs && text === s.prompt) break; // replayed after a reconnect
        s.promptTs = ts;
        // A message that follows the agent's question answers it; it does not replace the task.
        const answer = !!s.waitingUser; s.waitingUser = null; s.lastSay = null;
        s.active = true; s.ended = false; s.awaiting = true; s.prompt = text;
        if (!answer) s.task = short(text.split('\n').find(l => l.trim()) || text, 110);
        const tok = estTokens(Number(r.user_chars) || text.length);
        const card = this.card(s, { type: 'phone', label: answer ? 'user answer' : 'user prompt', tok, ok: true, ts });
        this.log(s, { ts, kind: 'phone', dir: 'in', label: short(text, 160), ok: true, tok });
        if (!answer) this.log(s, { ts, kind: 'board', label: 'Task: ' + s.task, ok: true, tok: 0 });
        if (s.attached) s.queue.push({ t: 'prompt', text, card, answer });
        break;
      }
      case 'tool_invoke': {
        if (r.call_id && s.seen.has(r.call_id)) break; // replayed after a reconnect
        if (r.call_id) s.seen.add(r.call_id);
        s.active = true; s.ended = false;
        if (!r.sub_id) this.demote(s); // the main agent carried on after speaking
        const kind = toolKind(r.tool_name, r.tool_arg), ask = !r.sub_id && isAskTool(r.tool_name);
        const call = { id: r.call_id || 'c' + (++this.seq), tool: r.tool_name, kind, ts, done: false, ok: true, tok: 0, error: '', subId: r.sub_id || '', sub: null, ask,
          label: ask ? short(r.ask_text || r.tool_arg || 'a question for the user', 160) : kind === 'sub' ? short('Sub-agent: ' + (r.sub_type || r.tool_arg || r.tool_name), 80) : toolLabel(r.tool_name, r.tool_arg) };
        s.calls++; s.open.set(call.id, call); this.index(s, call);
        const sub = call.subId ? this.sub(s, call.subId, r.sub_name, ts) : null;
        if (ask) { // a question put through a tool: the turn is blocked until the tool returns the answer
          const tok = estTokens(call.label.length), card = this.card(s, { type: 'reply', label: 'question to the user', tok, ok: true, ts });
          this.log(s, { ts, kind: 'phone', dir: 'out', label: call.label, ok: true, tok });
          s.reply = 'Asked: ' + call.label; s.waitingUser = { text: call.label, ts, call };
          if (s.attached) s.queue.push({ t: 'ask', text: call.label, card, call });
        } else
        if (s.attached) (sub ? sub.queue : s.queue).push({ t: 'call', call });
        const orphan = this.orphans.get(call.id); if (orphan) { this.orphans.delete(call.id); this.hook(orphan); }
        break;
      }
      case 'tool_complete': {
        s.active = true;
        let call = this.find(s, r.call_id, r.tool_name);
        if (!call && r.call_id && s.seen.has(r.call_id)) break; // already completed
        if (r.call_id) s.seen.add(r.call_id);
        if (!call) { // invoke fell outside the look-back window
          const kind = toolKind(r.tool_name, r.tool_arg);
          call = { id: r.call_id || 'c' + (++this.seq), tool: r.tool_name, kind, ts, done: false, ok: true, tok: 0, error: '', subId: r.sub_id || '', sub: null,
            label: kind === 'sub' ? short('Sub-agent: ' + (r.sub_type || r.tool_arg || r.tool_name), 80) : toolLabel(r.tool_name, r.tool_arg) };
          s.calls++;
          const sub = call.subId ? this.sub(s, call.subId, r.sub_name, ts) : null;
          if (s.attached) (sub ? sub.queue : s.queue).push({ t: 'call', call });
        }
        const ok = r.tool_success !== false && r.tool_success !== 0 && r.hook_decision !== 'block';
        this.finish(s, call, ok, estTokens(r.payload_chars), ts);
        break;
      }
      case 'llm_response': {
        s.active = true; s.awaiting = false; this.closeOpen(s, ts);
        const text = String(r.assistant_message || ''); if (!text) break;
        if (ts === s.replyTs && text === s.replyRaw) break; // replayed after a reconnect
        this.demote(s); // two messages in one turn: the earlier one was a progress update
        s.replyTs = ts; s.replyRaw = text;
        const ask = isQuestion(text), tok = estTokens(Number(r.assistant_chars) || text.length), prevReply = s.reply;
        const card = this.card(s, { type: 'reply', label: ask ? 'question to the user' : 'reply to the user', tok, ok: true, ts });
        const entry = { ts, kind: 'phone', dir: 'out', label: short(text, 160), ok: true, tok }; this.log(s, entry);
        s.reply = (ask ? 'Asked: ' : '') + short(text, 600);
        const wait = ask ? { text: short(text, 160), ts } : null; s.waitingUser = wait;
        s.lastSay = { t: ask ? 'ask' : 'say', text: short(text, 240), card, entry, wait, prevReply };
        if (s.attached) s.queue.push(s.lastSay);
        break;
      }
    }
  }

  // ---- raw hooks the CIM views drop (agentguard_hook_events) ----
  ingestHooks(rows) { for (const r of rows) this.hook(r); }
  hook(r) {
    const failed = r.hook_name === 'tool_call_failure' || r.hook_name === 'permission_denied';
    const s = this.sessions.get(r.session_id);
    // The raw hook can arrive before the CIM row for the same call: keep it until the call shows up.
    if (failed && r.call_id && !(s && s.open.has(r.call_id))) { if (!(s && s.seen.has(r.call_id))) { this.orphans.set(r.call_id, r); if (this.orphans.size > 500) this.orphans.delete(this.orphans.keys().next().value); } return; }
    if (r.hook_name === 'instructions_loaded' || r.hook_name === 'pre_compact' || r.hook_name === 'post_compact') return this.contextHook(r);
    if (r.hook_name === 'task_created' || r.hook_name === 'task_completed') { // the agent's own task list, shown on the board
      if (!r.session_id || !r.task_id) return;
      const t = this.session(r.session_id), done = r.hook_name === 'task_completed', cur = t.tasks.get(r.task_id);
      if (cur && cur.done === done) return;
      t.tasks.set(r.task_id, { subject: r.task_subject || (cur && cur.subject) || 'task ' + r.task_id, done });
      this.log(t, { ts: Number(r.ts) || 0, kind: 'board', label: (done ? 'Done: ' : 'New task: ') + t.tasks.get(r.task_id).subject, ok: true, tok: 0 });
      return;
    }
    if (r.hook_name === 'stop_failure') { // the turn died on an API error: no answer will come
      if (!s) return;
      s.awaiting = false; s.failures++; this.closeOpen(s, Number(r.ts) || 0);
      this.log(s, { ts: Number(r.ts) || 0, kind: 'agent', label: 'Turn ended by an API error' + (r.error ? ': ' + short(r.error, 120) : ''), ok: false, tok: 0 });
      return;
    }
    if (!s) return;
    const ts = Number(r.ts) || 0; if (ts > s.lastTs) s.lastTs = ts;
    if (r.hook_name === 'subagent_ended') {
      const sub = s.subs.get(r.sub_id); if (sub && !sub.ended) { sub.ended = true; const sp = s.subSpans.find(x => x.id === sub.id); if (sp && !sp.end) sp.end = ts; }
    } else if (failed) {
      const call = this.find(s, r.call_id, r.tool_name);
      if (call) { call.error = short(r.error || (r.hook_name === 'permission_denied' ? 'Permission denied' : 'Failed'), 200); this.finish(s, call, false, estTokens(call.error.length), ts); }
    }
  }

  // ---- instruction files and compaction (raw hooks) ----
  contextHook(r) {
    if (!r.session_id) return;
    const s = this.session(r.session_id), ts = Number(r.ts) || 0; if (ts > s.lastTs) s.lastTs = ts;
    if (r.hook_name === 'pre_compact') { // compaction is starting: the robot tidies until it completes
      s.compactHooks = true;
      if (!s.compactJob || s.compactJob.done) { s.compactJob = { start: ts, done: false, card: null, trigger: r.compact_trigger || '' }; if (s.attached) s.queue.push({ t: 'compact', job: s.compactJob }); }
    } else if (r.hook_name === 'post_compact') this.compacted(s, ts);
    else { // a CLAUDE.md or rules file was put into context without any tool call
      const key = 'i' + ts + r.file_path; if (s.enriched.has(key)) return; s.enriched.add(key);
      const file = String(r.file_path || 'instructions').split('/').slice(-2).join('/'), why = String(r.load_reason || '').replace(/_/g, ' ');
      const label = short('Load ' + file + ' (' + [r.memory_type, why].filter(Boolean).join(', ') + ')', 90);
      s.memoryOps.load = (s.memoryOps.load || 0) + 1; s.active = s.active || false;
      const card = this.card(s, { type: 'memory', label, tok: 0, ok: true, ts, unknownSize: true });
      this.log(s, { ts, kind: 'memory', label, ok: true, tok: 0 });
      if (s.attached) s.queue.push({ t: 'load', card, label });
    }
  }
  /** The context was compacted: every card collapses into one summary. Reported twice by some versions, so debounce. */
  compacted(s, ts, inferred = false) {
    if (s.lastCompact && Math.abs(ts - s.lastCompact) < 60000) return; s.lastCompact = ts; if (!inferred) s.compactHooks = true;
    const n = s.cards.length; s.cards = [];
    const card = this.card(s, { type: 'bench', label: 'summary of ' + n + ' cards', tok: inferred ? Math.max(0, s.ctx) : 0, ok: true, ts, real: inferred, unknownSize: !inferred });
    this.log(s, { ts, kind: 'bench', label: 'Compacted ' + n + ' cards into one summary' + (inferred ? ' (inferred from context size)' : ''), ok: true, tok: 0 });
    let job = s.compactJob; const fresh = !job || job.done;
    if (fresh) job = s.compactJob = { start: ts, done: false, card: null, trigger: '' };
    job.done = true; job.card = card; s.summaryCard = inferred ? null : card;
    if (fresh && s.attached) s.queue.push({ t: 'compact', job });
  }

  // ---- skills and memory (agentguard_skills, agentguard_memory_ops) ----
  // Both streams are derived from the same "before tool call" hook as tool_invoke, so a row shares
  // its timestamp with the call it describes. Rows give the call its proper name and operation.
  ingestSkills(rows) { for (const r of rows) this.skill(r); }
  skill(r) {
    if (!r.session_id || !r.skill_name) return;
    const s = this.session(r.session_id), ts = Number(r.ts) || 0;
    if (r.skill_action !== 'invoked') { s.skillsAvailable.add(r.skill_name); return; } // listed in the prompt, not used
    s.skillsUsed.set(r.skill_name, (s.skillsUsed.get(r.skill_name) || 0) + (s.enriched.has('s' + ts + r.skill_name) ? 0 : 1)); s.enriched.add('s' + ts + r.skill_name);
    this.enrich(s, ts, { kind: 'skill', label: short('Load skill: ' + r.skill_name, 80), meta: { skill: r.skill_name, source: r.skill_source_type || '', namespace: r.skill_namespace || '' } });
  }
  ingestMemory(rows) { for (const r of rows) this.memory(r); }
  memory(r) {
    if (!r.session_id) return;
    const s = this.session(r.session_id), ts = Number(r.ts) || 0, op = r.memory_op || 'use', key = 'm' + ts + r.tool_name;
    if (!s.enriched.has(key)) { s.enriched.add(key); s.memoryOps[op] = (s.memoryOps[op] || 0) + 1; }
    const what = r.memory_path ? ': ' + String(r.memory_path).split('/').pop() : r.server_name ? ' · ' + String(r.server_name).replace(/^plugin_/, '') : '';
    this.enrich(s, ts, { kind: 'memory', label: short(op[0].toUpperCase() + op.slice(1) + ' memory' + what, 80), meta: { op, source: r.memory_source || '', server: r.server_name || '', path: r.memory_path || '' } });
  }
  enrich(s, ts, info) {
    const call = s.byTs.get(ts);
    if (!call) { s.pendingEnrich.set(ts, info); if (s.pendingEnrich.size > 200) s.pendingEnrich.delete(s.pendingEnrich.keys().next().value); return; }
    if (!call.done) call.kind = info.kind; // a robot already on its way keeps its destination
    call.label = info.label; call.meta = info.meta;
    if (call.card) call.card.label = info.label;
    if (call.logEntry) call.logEntry.label = info.label + (call.error ? ' · ' + call.error : '');
  }
  index(s, call) {
    s.byTs.set(call.ts, call); if (s.byTs.size > 300) s.byTs.delete(s.byTs.keys().next().value);
    const info = s.pendingEnrich.get(call.ts); if (info) { s.pendingEnrich.delete(call.ts); this.enrich(s, call.ts, info); }
  }

  // ---- token metrics (agentguard_cim_metrics) ----
  ingestMetrics(rows) { for (const r of rows) this.metric(r); }
  metric(r) {
    if (!r.session_id) return;
    const s = this.session(r.session_id), ts = Number(r.ts) || 0, p = s.pending; // metrics may arrive before the first event
    if (p && p.ts !== ts) this.commit(s);
    if (!s.pending) s.pending = { ts, sum: 0, model: r.model || '', at: Date.now() };
    s.pending.sum += Number(r.metric_value) || 0;
  }
  /** Close metric groups that have stopped receiving rows. Call about once a second. */
  flush(now = Date.now()) { for (const s of this.sessions.values()) if (s.pending && now - s.pending.at > 1200) this.commit(s); }
  commit(s) {
    const p = s.pending; s.pending = null; if (!p || p.sum <= 0) return;
    // One LLM call's prompt size = input + cache read + cache write. Calls made by sub-agents or by a
    // helper model share the session id, so skip them: they are not the main agent's context.
    if (!s.mainModel) s.mainModel = s.model || p.model;
    if (p.model && s.mainModel && p.model !== s.mainModel) return;
    if (s.subSpans.some(x => p.ts >= x.start && (!x.end || p.ts <= x.end + 500))) return;
    const prev = s.ctxReal ? s.ctx : 0;
    s.ctx = p.sum; s.ctxReal = true; if (s.ctx > 200000) s.ctxLimit = 1000000;
    s.hist.push({ ts: p.ts, v: s.ctx }); if (s.hist.length > MAX_HIST) s.hist.shift();
    if (s.summaryCard && p.ts > s.lastCompact) { s.summaryCard.tok = s.ctx; s.summaryCard.real = true; s.summaryCard.unknownSize = false; s.summaryCard = null; } // first call after a compaction sizes the summary
    // No compaction event for this agent: infer it from a sharp drop in context size.
    else if (!s.compactHooks && prev > 0 && s.ctx < prev * 0.6 && prev - s.ctx > 20000) this.compacted(s, p.ts, true);
  }

  // ---- helpers ----
  sub(s, id, name, ts) {
    let sub = s.subs.get(id);
    if (!sub) {
      sub = { id, name: name || 'sub-agent', call: null, queue: [], ended: false, startTs: ts, cards: 0 };
      s.subs.set(id, sub); s.subSpans.push({ id, start: ts, end: 0 });
      const call = [...s.open.values()].find(c => c.kind === 'sub' && !c.sub && !c.subId);
      if (call) { call.sub = sub; sub.call = call; } else if (s.attached) s.queue.push({ t: 'sub', sub });
    } else if (name && sub.name === 'sub-agent') sub.name = name;
    return sub;
  }
  /** Sub-agent for a delegation call that never announced one (agents without a sub-agent start hook). */
  ensureSub(s, call) { if (!call.sub) { const sub = this.sub(s, 'call:' + call.id, call.label.replace(/^Sub-agent: /, ''), call.ts); sub.call = call; call.sub = sub; } return call.sub; }
  find(s, id, tool) {
    if (id && s.open.has(id)) return s.open.get(id);
    if (id) return null;
    for (const c of s.open.values()) if (c.tool === tool) return c;
    return null;
  }
  finish(s, call, ok, tok, ts) {
    if (call.done) return;
    call.done = true; call.ok = ok; call.tok = tok; call.endTs = ts; s.open.delete(call.id);
    if (!ok) s.failures++;
    if (call.sub) { call.sub.ended = true; const sp = s.subSpans.find(x => x.id === call.sub.id); if (sp && !sp.end) sp.end = ts; }
    const inSub = !!call.subId, kind = call.kind === 'sub' ? 'subbench' : call.kind;
    if (!call.ask) { call.logEntry = { ts, kind, label: call.label + (call.error ? ' · ' + call.error : ''), ok, tok, sub: inSub }; this.log(s, call.logEntry); }
    if (inSub) { const sub = s.subs.get(call.subId); if (sub) sub.cards++; }
    else if (call.ask) { // the tool returned: that is the user's answer
      if (s.waitingUser && s.waitingUser.call === call) s.waitingUser = null;
      call.logEntry = { ts, kind: 'phone', dir: 'in', label: ok ? 'Answered: ' + call.label : 'No answer: ' + call.label, ok, tok }; this.log(s, call.logEntry);
      call.card = this.card(s, { type: 'phone', label: 'user answer', tok, ok, ts }); s.awaiting = true;
    }
    else { call.card = this.card(s, { type: kind, label: call.kind === 'sub' ? 'result: ' + call.label.replace(/^Sub-agent: /, '') : call.label, tok, ok, ts }); s.awaiting = true; }
  }
  /** A turn ended: anything still open will not report back (interrupted or lost). */
  closeOpen(s, ts) { for (const c of [...s.open.values()]) { c.done = true; c.unknown = true; c.endTs = ts; s.open.delete(c.id); if (c.sub) c.sub.ended = true; if (s.waitingUser && s.waitingUser.call === c) s.waitingUser = null; } for (const sp of s.subSpans) if (!sp.end) sp.end = ts; for (const sub of s.subs.values()) sub.ended = true; }
  card(s, c) { s.cards.push(c); if (s.cards.length > MAX_CARDS) s.cards.shift(); if (!s.ctxReal) s.ctx = s.cards.reduce((a, x) => a + x.tok, 0); return c; }
  log(s, e) { s.log.push(e); s.logN = (s.logN || 0) + 1; if (s.log.length > MAX_LOG) s.log.shift(); } // logN counts every entry, kept or not
}
