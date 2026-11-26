import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Store } from '../../web/agent-rooms/src/store.js';

// Row shapes as returned by the queries in src/queries.js (captured from a real Claude Code session).
const S = 'sess-1';
const ev = (ts, event_type, x = {}) => ({ ts, event_type, session_id: S, agent_type: 'claudecode', agent_id: 'host.local', cwd: '/w/AgentGuard', tool_success: true, hook_decision: 'observe', ...x });

function run() {
  const st = new Store();
  st.ingestEvents([ev(1000, 'session_start'), ev(1100, 'user_input', { user_message: 'Fix the login bug\nplease', user_chars: 24 })]);
  const s = st.sessions.get(S); st.attach(s, 2000);
  return { st, s };
}

test('a prompt sets the task and queues a prompt item', () => {
  const { s } = run(); // attached after the prompt, so nothing is queued for it
  assert.equal(s.task, 'Fix the login bug'); assert.equal(s.name, 'AgentGuard · sess-1'); assert.equal(s.badge, 'CC');
  assert.equal(s.cards.length, 1); assert.equal(s.queue.length, 0); assert.equal(s.awaiting, true);
});

test('tool invoke and complete pair by call id and produce one card', () => {
  const { st, s } = run();
  st.event(ev(1200, 'tool_invoke', { tool_name: 'Read', tool_arg: '/w/src/a.ts', call_id: 't1' }));
  assert.equal(s.open.size, 1); assert.equal(s.queue[0].call.kind, 'files'); assert.equal(st.resting(s, 1300), false);
  st.event(ev(1290, 'tool_complete', { tool_name: 'Read', call_id: 't1', payload_chars: 4000 }));
  const c = s.queue[0].call;
  assert.equal(c.done, true); assert.equal(c.ok, true); assert.equal(c.tok, 1000); assert.equal(s.open.size, 0);
  assert.equal(s.cards.at(-1), c.card); assert.equal(s.log.at(-1).kind, 'files'); assert.equal(s.calls, 1);
  st.event(ev(1200, 'tool_invoke', { tool_name: 'Read', call_id: 't1' })); // replay after reconnect
  assert.equal(s.calls, 1);
});

test('a failure hook closes the call as failed, even when it arrives first', () => {
  const { st, s } = run();
  st.event(ev(1200, 'tool_invoke', { tool_name: 'Bash', tool_arg: 'cat /nope', call_id: 't2' }));
  st.hook({ ts: 1300, session_id: S, hook_name: 'tool_call_failure', tool_name: 'Bash', call_id: 't2', error: 'Exit code 1' });
  assert.equal(s.failures, 1); assert.equal(s.cards.at(-1).ok, false); assert.match(s.log.at(-1).label, /Exit code 1/);
  st.hook({ ts: 1400, session_id: S, hook_name: 'tool_call_failure', tool_name: 'Bash', call_id: 't3', error: 'late' });
  st.event(ev(1390, 'tool_invoke', { tool_name: 'Bash', tool_arg: 'false', call_id: 't3' }));
  assert.equal(s.failures, 2); assert.equal(s.open.size, 0);
});

test('sub-agent calls go to the sub-agent, and only its result reaches the main bench', () => {
  const { st, s } = run(), before = s.cards.length;
  st.event(ev(2000, 'tool_invoke', { tool_name: 'Agent', sub_type: 'Explore', call_id: 'a1' }));
  st.event(ev(2100, 'session_start', { raw_hook_name: 'subagent_spawning', sub_id: 'sub9', sub_name: 'Explore' }));
  const sub = s.subs.get('sub9'), agentCall = s.queue[0].call;
  assert.equal(agentCall.kind, 'sub'); assert.equal(agentCall.sub, sub); assert.equal(sub.name, 'Explore');
  st.event(ev(2200, 'tool_invoke', { tool_name: 'Grep', call_id: 'g1', sub_id: 'sub9' }));
  st.event(ev(2300, 'tool_complete', { tool_name: 'Grep', call_id: 'g1', sub_id: 'sub9', payload_chars: 400 }));
  assert.equal(sub.queue.length, 1); assert.equal(s.queue.length, 1); assert.equal(s.cards.length, before); assert.equal(sub.cards, 1);
  st.hook({ ts: 2400, session_id: S, hook_name: 'subagent_ended', sub_id: 'sub9' });
  st.event(ev(2500, 'tool_complete', { tool_name: 'Agent', call_id: 'a1', payload_chars: 1200 }));
  assert.equal(sub.ended, true); assert.equal(s.cards.length, before + 1); assert.equal(s.cards.at(-1).type, 'subbench');
});

test('context size comes from token metrics of the main model only; a sharp drop is a compaction', () => {
  const { st, s } = run();
  const m = (ts, v, model = 'sonnet') => ['llm.input_tokens', 'llm.cache_read_tokens', 'llm.cache_write_tokens'].map((metric_name, i) => ({ ts, session_id: S, metric_name, metric_value: i === 1 ? v : 0, model }));
  assert.equal(s.ctxReal, false);
  st.ingestMetrics([...m(3000, 90000), ...m(3100, 14000, 'haiku'), ...m(3200, 120000), ...m(3300, 30000)]);
  st.flush(Date.now() + 5000);
  assert.equal(s.ctxReal, true); assert.equal(s.ctx, 30000); assert.deepEqual(s.hist.map(x => x.v), [90000, 120000, 30000]);
  assert.equal(s.cards.length, 1); assert.match(s.cards[0].label, /summary of 1 cards/); assert.equal(s.queue.at(-1).t, 'compact'); assert.equal(s.queue.at(-1).job.done, true);
  st.ingestMetrics(m(3400, 320000)); st.flush(Date.now() + 5000);
  assert.equal(s.ctxLimit, 1000000);
});

test('a final answer ends the turn; session end puts the agent to rest', () => {
  const { st, s } = run();
  st.event(ev(4000, 'tool_invoke', { tool_name: 'Bash', call_id: 'x1' }));
  st.event(ev(5000, 'llm_response', { assistant_message: 'Done.', model: 'claude-sonnet' }));
  assert.equal(s.open.size, 0); assert.equal(s.queue.at(-1).t, 'say'); assert.equal(s.model, 'claude-sonnet'); assert.equal(st.resting(s, 5001), true);
  st.event(ev(6000, 'session_end')); assert.equal(s.ended, true);
  assert.deepEqual(st.top(5), [s]);
});

test('skill and memory rows name the call they share a timestamp with, in either arrival order', () => {
  const { st, s } = run();
  st.event(ev(7000, 'tool_invoke', { tool_name: 'Skill', tool_arg: 'tdd', call_id: 'k1' }));
  st.skill({ ts: 7000, session_id: S, skill_name: 'tdd', skill_action: 'invoked', skill_source_type: 'user' });
  st.event(ev(7090, 'tool_complete', { tool_name: 'Skill', call_id: 'k1', payload_chars: 80 }));
  assert.equal(s.cards.at(-1).label, 'Load skill: tdd'); assert.equal(s.cards.at(-1).type, 'skill'); assert.equal(s.skillsUsed.get('tdd'), 1);
  st.skill({ ts: 7000, session_id: S, skill_name: 'tdd', skill_action: 'invoked' }); // replay
  assert.equal(s.skillsUsed.get('tdd'), 1);
  st.skill({ ts: 7001, session_id: S, skill_name: 'pdf', skill_action: 'loaded' });
  assert.equal(s.skillsAvailable.size, 1); assert.equal(s.skillsUsed.has('pdf'), false);

  st.memory({ ts: 8000, session_id: S, memory_source: 'auto_memory', memory_op: 'read', tool_name: 'Read', memory_path: '/p/memory/MEMORY.md' }); // before the call
  st.event(ev(8000, 'tool_invoke', { tool_name: 'Read', tool_arg: '/p/memory/MEMORY.md', call_id: 'm1' }));
  st.event(ev(8080, 'tool_complete', { tool_name: 'Read', call_id: 'm1', payload_chars: 400 }));
  st.event(ev(8100, 'tool_invoke', { tool_name: 'mcp__mem__search', call_id: 'm2' }));
  st.event(ev(8200, 'tool_complete', { tool_name: 'mcp__mem__search', call_id: 'm2', payload_chars: 40 }));
  st.memory({ ts: 8100, session_id: S, memory_source: 'mcp', memory_op: 'search', tool_name: 'mcp__mem__search', server_name: 'mem' }); // after completion
  const labels = s.log.filter(x => x.kind === 'memory').map(x => x.label);
  assert.deepEqual(labels, ['Read memory: MEMORY.md', 'Search memory · mem']); assert.deepEqual(s.memoryOps, { read: 1, search: 1 });
  assert.equal(s.cards.at(-1).label, 'Search memory · mem');
});

test('instruction files loaded without a tool call show up as memory loads', () => {
  const { st, s } = run(), n = s.cards.length;
  const row = { ts: 900, session_id: S, hook_name: 'instructions_loaded', file_path: '/w/AgentGuard/CLAUDE.md', memory_type: 'Project', load_reason: 'session_start' };
  st.hook(row); st.hook(row); // second is a replay
  assert.equal(s.memoryOps.load, 1); assert.equal(s.cards.length, n + 1);
  assert.equal(s.log.at(-1).label, 'Load AgentGuard/CLAUDE.md (Project, session start)'); assert.equal(s.queue.at(-1).t, 'load');
});

test('compaction is taken from real events when the agent reports them', () => {
  const { st, s } = run();
  st.hook({ ts: 9000, session_id: S, hook_name: 'pre_compact', compact_trigger: 'manual' });
  const job = s.queue.at(-1).job; assert.equal(job.done, false); assert.equal(s.cards.length, 1);
  st.event(ev(16000, 'session_start', { source: 'compact' }));
  st.hook({ ts: 16010, session_id: S, hook_name: 'post_compact' }); // same compaction reported again
  assert.equal(job.done, true); assert.equal(s.cards.length, 1); assert.equal(job.card, s.cards[0]); assert.match(job.card.label, /summary of 1 cards/);
  assert.equal(s.queue.filter(x => x.t === 'compact').length, 1); assert.equal(s.ended, false);
  const m = (ts, v) => ['llm.input_tokens', 'llm.cache_read_tokens', 'llm.cache_write_tokens'].map((metric_name, i) => ({ ts, session_id: S, metric_name, metric_value: i === 1 ? v : 0, model: 'sonnet' }));
  st.ingestMetrics([...m(8000, 150000), ...m(17000, 30000)]); st.flush(Date.now() + 5000);
  assert.equal(job.card.tok, 30000); assert.equal(s.cards.length, 1); // sized by the next call, not compacted a second time
});

test('task list and API-error turn ends come from raw hooks', () => {
  const { st, s } = run();
  st.hook({ ts: 9100, session_id: S, hook_name: 'task_created', task_id: '1', task_subject: 'check version' });
  st.hook({ ts: 9200, session_id: S, hook_name: 'task_completed', task_id: '1', task_subject: 'check version' });
  st.hook({ ts: 9200, session_id: S, hook_name: 'task_completed', task_id: '1', task_subject: 'check version' });
  assert.deepEqual([...s.tasks.values()], [{ subject: 'check version', done: true }]);
  assert.deepEqual(s.log.slice(-2).map(x => x.label), ['New task: check version', 'Done: check version']);
  st.event(ev(9300, 'tool_invoke', { tool_name: 'Bash', call_id: 'z1' }));
  st.hook({ ts: 9400, session_id: S, hook_name: 'stop_failure', error: 'rate_limit' });
  assert.equal(s.open.size, 0); assert.equal(s.awaiting, false); assert.equal(st.resting(s, 9401), true);
});

// ---- the conversation with the user, both ways ----
test('a reply at the end of a turn is logged to the user, with a reply card sized by its length', () => {
  const { st, s } = run();
  st.event(ev(5000, 'llm_response', { assistant_message: 'Fixed. A stale session cookie caused the redirect.', assistant_chars: 400 }));
  const it = s.queue.at(-1), e = s.log.at(-1);
  assert.equal(it.t, 'say'); assert.equal(it.card.type, 'reply'); assert.equal(it.card.label, 'reply to the user'); assert.equal(it.card.tok, 100);
  assert.deepEqual([e.kind, e.dir, e.tok], ['phone', 'out', 100]);
  assert.equal(s.reply, 'Fixed. A stale session cookie caused the redirect.'); assert.equal(s.waitingUser, null);
  assert.equal(s.cards.at(-1), it.card);
  st.event(ev(5000, 'llm_response', { assistant_message: 'Fixed. A stale session cookie caused the redirect.' })); // replay after reconnect
  assert.equal(s.queue.filter(x => x.t === 'say').length, 1);
});

test('a turn that ends on a question blocks on the user until they answer; the answer keeps the task', () => {
  const { st, s } = run();
  st.event(ev(5000, 'llm_response', { assistant_message: 'I found two options.\n\nShould a stale cookie sign the user out?' }));
  const ask = s.queue.at(-1);
  assert.equal(ask.t, 'ask'); assert.equal(ask.card.label, 'question to the user');
  assert.ok(s.waitingUser); assert.equal(s.waitingUser, ask.wait); assert.match(s.reply, /^Asked: I found two options/);
  st.event(ev(9000, 'user_input', { user_message: 'Sign them out.' }));
  const ans = s.queue.at(-1);
  assert.equal(s.waitingUser, null); assert.equal(ans.t, 'prompt'); assert.equal(ans.answer, true); assert.equal(ans.card.label, 'user answer');
  assert.equal(s.task, 'Fix the login bug'); assert.equal(s.prompt, 'Sign them out.');
  assert.deepEqual([s.log.at(-1).kind, s.log.at(-1).dir], ['phone', 'in']); // no "Task:" entry for an answer
  st.event(ev(9500, 'user_input', { user_message: 'Now add a test' }));
  assert.equal(s.queue.at(-1).answer, false); assert.equal(s.task, 'Now add a test'); assert.equal(s.log.at(-1).kind, 'board');
});

test('an assistant message followed by more tool calls was a progress update, not a reply', () => {
  const { st, s } = run();
  st.event(ev(5000, 'llm_response', { assistant_message: 'Final answer one.' }));
  st.event(ev(6000, 'user_input', { user_message: 'next' }));
  st.event(ev(7000, 'llm_response', { assistant_message: 'Two tests fail. Bringing in helpers?' }));
  const it = s.queue.at(-1), cards = s.cards.length;
  assert.equal(it.t, 'ask'); assert.ok(s.waitingUser);
  st.event(ev(7100, 'tool_invoke', { tool_name: 'Bash', call_id: 'n1' }));
  assert.equal(it.t, 'note'); assert.equal(it.card, null); assert.equal(s.cards.length, cards - 1);
  assert.equal(s.waitingUser, null); assert.equal(s.reply, 'Final answer one.');
  const e = s.log.find(x => x.label.startsWith('Two tests fail'));
  assert.deepEqual([e.kind, e.dir, e.tok], ['note', undefined, 0]);
  assert.equal(s.queue.at(-1).t, 'call');
});
test('a message the robot already took to the phone stays a reply', () => {
  const { st, s } = run();
  st.event(ev(7000, 'llm_response', { assistant_message: 'Working on it.' }));
  const it = s.queue.at(-1); it.taken = true; // the scene dequeued it
  st.event(ev(7100, 'tool_invoke', { tool_name: 'Bash', call_id: 'n1' }));
  assert.equal(it.t, 'say'); assert.ok(it.card); assert.equal(s.reply, 'Working on it.');
});
test('a sub-agent tool call does not turn the main agent\'s reply into a note', () => {
  const { st, s } = run();
  st.event(ev(7000, 'llm_response', { assistant_message: 'Done.' }));
  const it = s.queue.at(-1);
  st.event(ev(7100, 'tool_invoke', { tool_name: 'Read', call_id: 's1', sub_id: 'a9', sub_name: 'Explore' }));
  assert.equal(it.t, 'say');
});

test('an ask-the-user tool call blocks on the user until the tool returns the answer', () => {
  const { st, s } = run();
  st.event(ev(5000, 'tool_invoke', { tool_name: 'AskUserQuestion', call_id: 'q1', ask_text: 'Apply migration 041 to production now?' }));
  const it = s.queue.at(-1);
  assert.equal(it.t, 'ask'); assert.equal(it.text, 'Apply migration 041 to production now?'); assert.equal(it.card.type, 'reply');
  assert.equal(s.waitingUser.call, it.call); assert.equal(s.reply, 'Asked: Apply migration 041 to production now?');
  assert.deepEqual([s.log.at(-1).kind, s.log.at(-1).dir], ['phone', 'out']);
  assert.equal(st.resting(s, 5001), false);
  st.event(ev(9000, 'tool_complete', { tool_name: 'AskUserQuestion', call_id: 'q1', payload_chars: 80 }));
  assert.equal(s.waitingUser, null); assert.equal(it.call.done, true); assert.equal(it.call.card.label, 'user answer'); assert.equal(it.call.card.type, 'phone');
  assert.deepEqual([s.log.at(-1).kind, s.log.at(-1).dir], ['phone', 'in']);
  assert.equal(s.log.filter(x => x.kind === 'other').length, 0); // not also logged as an ordinary tool call
});
test('a session that is already blocked on the user is picked up holding the line', () => {
  const { st, s } = run();
  st.event(ev(5000, 'llm_response', { assistant_message: 'Which one?' }));
  st.detach(s); st.attach(s, 6000);
  assert.deepEqual(s.queue.map(x => [x.t, x.resume, x.wait === s.waitingUser]), [['ask', true, true]]);
  st.event(ev(7000, 'session_end')); assert.equal(s.waitingUser, null);
});

// ---- Codex (timeplus-io/apps#69). Row shapes from spans sent by the AgentGuard Codex plugin 0.2.0. ----
const C = 'codex-1';
const cx = (ts, event_type, x = {}) => ({ ts, event_type, session_id: C, agent_type: 'codex', agent_id: 'host.local', cwd: '/w/demo-repo', model: 'gpt-5-codex', tool_success: true, hook_decision: '', ...x });
function codex() {
  const st = new Store();
  st.ingestEvents([cx(1000, 'session_start', { raw_hook_name: 'session_start' }), cx(1100, 'user_input', { user_message: 'say hello and list files', user_chars: 24, raw_hook_name: 'user_prompt_submit' })]);
  const s = st.sessions.get(C); st.attach(s, 1200);
  return { st, s };
}
test('a Codex session has a badge, a model, a name from its directory, and its prompt', () => {
  const { s } = codex();
  assert.deepEqual([s.badge, s.typeName, s.model, s.name], ['CX', 'Codex', 'gpt-5-codex', 'demo-repo · codex-1']);
  assert.equal(s.task, 'say hello and list files'); assert.equal(s.awaiting, true); assert.equal(s.cards[0].type, 'phone');
});
test('a Codex model request does not end the turn; its stop does, with the reply', () => {
  const { st, s } = codex();
  st.event(cx(1900, 'llm_response', { raw_hook_name: 'post_model_request' }));
  assert.equal(s.awaiting, true); assert.equal(st.resting(s, 2000), false);
  st.event(cx(2000, 'tool_invoke', { tool_name: 'Bash', tool_arg: 'ls', call_id: 'c1' }));
  st.event(cx(2100, 'tool_complete', { tool_name: 'Bash', tool_arg: 'ls', call_id: 'c1', payload_chars: 400 }));
  assert.equal(s.cards.at(-1).type, 'files'); // a read through the shell
  st.event(cx(2500, 'llm_response', { raw_hook_name: 'post_model_request' }));
  st.event(cx(2600, 'llm_response', { raw_hook_name: 'stop', assistant_message: 'hello, README.md', assistant_chars: 16 }));
  assert.equal(s.awaiting, false); assert.equal(s.reply, 'hello, README.md'); assert.equal(s.cards.at(-1).type, 'reply');
  assert.equal(st.resting(s, 2700), true);
});
test('Codex context size is its input tokens: cached tokens are already part of them', () => {
  const { st, s } = codex();
  const m = (metric_name, metric_value) => ({ ts: 3000, session_id: C, agent_type: 'codex', metric_name, metric_value, model: 'gpt-5-codex' });
  st.ingestMetrics([m('llm.input_tokens', 19947), m('llm.cache_read_tokens', 9472)]); st.flush(Date.now() + 5000);
  assert.equal(s.ctx, 19947); assert.equal(s.ctxReal, true);
});
test('a Codex sub-agent, its stop, compaction, an interrupt and a permission request come through', () => {
  const { st, s } = codex();
  st.event(cx(2000, 'session_start', { sub_id: 'a7', sub_name: 'explorer', raw_hook_name: 'subagent_start' }));
  assert.equal(s.subs.get('a7').name, 'explorer');
  st.event(cx(2100, 'tool_invoke', { tool_name: 'Bash', tool_arg: 'git log', call_id: 'c2', sub_id: 'a7' }));
  st.event(cx(2200, 'tool_complete', { tool_name: 'Bash', tool_arg: 'git log', call_id: 'c2', sub_id: 'a7' }));
  assert.equal(s.subs.get('a7').cards, 1);
  const hk = (ts, hook_name, x = {}) => ({ ts, session_id: C, agent_type: 'codex', hook_name, ...x });
  st.ingestHooks([hk(2300, 'subagent_ended', { sub_id: 'a7' })]); assert.equal(s.subs.get('a7').ended, true);
  st.ingestHooks([hk(2400, 'permission_request', { tool_name: 'Bash', perm_arg: 'rm -rf build' })]);
  assert.deepEqual([s.log.at(-1).kind, s.log.at(-1).label], ['phone', 'Asked permission: Bash rm -rf build']);
  st.ingestHooks([hk(2500, 'pre_compact', { compact_trigger: 'auto' })]); assert.equal(s.compactJob.done, false);
  st.ingestHooks([hk(2600, 'post_compact', { compact_trigger: 'auto' })]); assert.equal(s.compactJob.done, true);
  st.event(cx(2700, 'tool_invoke', { tool_name: 'webrun', tool_arg: 'x', call_id: 'c3' })); assert.equal(s.open.size, 1);
  const n = s.log.length;
  st.ingestHooks([hk(2800, 'interrupt'), hk(2800, 'interrupt')]); // replayed after a reconnect: logged once
  assert.equal(s.open.size, 0); assert.equal(s.awaiting, false); assert.equal(s.log.length, n + 1); assert.equal(s.log.at(-1).label, 'Turn interrupted by the user');
});
test('a Codex plan replaces the task list on the board', () => {
  const { st, s } = codex();
  const plan = steps => JSON.stringify({ plan: steps.map(([step, status]) => ({ step, status })) });
  st.event(cx(2000, 'tool_invoke', { tool_name: 'update_plan', call_id: 'p1', plan: plan([['Read', 'in_progress'], ['Fix', 'pending']]) }));
  assert.deepEqual([...s.tasks.values()], [{ subject: 'Read', done: false }, { subject: 'Fix', done: false }]);
  st.event(cx(2100, 'tool_complete', { tool_name: 'update_plan', call_id: 'p1' }));
  st.event(cx(3000, 'tool_invoke', { tool_name: 'update_plan', call_id: 'p2', plan: plan([['Read', 'completed'], ['Fix', 'in_progress']]) }));
  assert.equal(s.tasks.get('plan0').done, true); assert.equal(s.log.filter(e => e.kind === 'board').at(-1).label, 'Plan: 1 of 2 steps done');
});
test('a Codex skill read is named from the skills stream', () => {
  const { st, s } = codex();
  st.event(cx(2000, 'tool_invoke', { tool_name: 'Bash', tool_arg: 'cat /h/.codex/skills/.system/openai-docs/SKILL.md', call_id: 'c4' }));
  assert.equal(s.open.get('c4').kind, 'skill');
  st.ingestSkills([{ ts: 2000, session_id: C, skill_name: 'openai-docs', skill_action: 'invoked', skill_source_type: 'system' }]);
  assert.equal(s.open.get('c4').kind, 'skill'); // already from the command, so it holds when the skills row arrives after the call has finished
  assert.equal(s.open.get('c4').label, 'Load skill: openai-docs'); assert.equal(s.skillsUsed.get('openai-docs'), 1);
});
