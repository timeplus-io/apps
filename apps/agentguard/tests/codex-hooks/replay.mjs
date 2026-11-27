// Live check of the Codex hook-event path (timeplus-io/apps#71). Needs a Timeplus with this app installed.
//
// hook-rows.json is one Codex session as the AgentGuard Codex plugin 0.3.0 writes it with
// AGENTGUARD_CODEX_EXPORT=hooks: all 14 hooks, a failed and a retried model request, a skill read,
// a plan, a permission request, one sub-agent, one compaction and an interrupted second turn.
// This script writes those rows to agentguard_hook_events under a new session id, waits for the
// views, and checks the CIM rows, the metrics, the skill row, and the room Agent Rooms builds from
// its own queries.
//
//   TIMEPLUS_URL=http://localhost:8123 TIMEPLUS_USER=... TIMEPLUS_PASSWORD=... make test-codex-hooks
//
// TIMEPLUS_URL is the SQL-over-HTTP port of timeplusd (8123). TIMEPLUS_DB defaults to `ag`.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { eventsSQL, metricsSQL, hooksSQL, skillsSQL } from '../../web/agent-rooms/src/queries.js';
import { Store } from '../../web/agent-rooms/src/store.js';

const URL_ = (process.env.TIMEPLUS_URL || 'http://localhost:8123').replace(/\/$/, '');
const DB = process.env.TIMEPLUS_DB || 'ag';
const USER = process.env.TIMEPLUS_USER || 'default', PASSWORD = process.env.TIMEPLUS_PASSWORD || '';
const FIXTURE_SESSION = 'codex-hooks-fixture';
const SESSION = 'codex-hooks-' + Date.now().toString(36);

async function post(sql, body = '') {
  const res = await fetch(URL_ + '/?query=' + encodeURIComponent(sql), {
    method: 'POST', body: body || undefined,
    headers: { Authorization: 'Basic ' + Buffer.from(USER + ':' + PASSWORD).toString('base64') },
  });
  const text = await res.text();
  if (!res.ok) throw new Error(text.trim() + '\n  in: ' + sql.slice(0, 300));
  return text;
}
const rows = async sql => (await post(sql + ' FORMAT JSONEachRow')).split('\n').filter(Boolean).map(l => JSON.parse(l));
const mine = `session_id = '${SESSION}'`;
const from = stream => `FROM table(${DB}.${stream}) WHERE ${mine}`;

// ---- write the recorded rows, moved to now so they fall inside the page's look-back window ----
const fixture = JSON.parse(readFileSync(new URL('./hook-rows.json', import.meta.url), 'utf8'));
const col = name => fixture.columns.indexOf(name);
const times = fixture.data.map(r => Date.parse(r[col('event_time')]));
const shift = Date.now() - Math.max(...times);
const stamp = ms => new Date(ms).toISOString().replace('T', ' ').replace('Z', '');
const lines = fixture.data.map((r, i) => {
  const row = r.map(v => typeof v === 'string' ? v.replaceAll(FIXTURE_SESSION, SESSION) : v);
  row[col('event_time')] = stamp(times[i] + shift);
  return JSON.stringify(row);
});
await post(`INSERT INTO ${DB}.agentguard_hook_events (${fixture.columns.join(', ')}) FORMAT JSONCompactEachRow`, lines.join('\n'));

// ---- wait for the views ----
const EXPECT = { agentguard_cim_event: 22, agentguard_cim_metrics: 33, agentguard_skills: 1 };
const counts = async () => Object.fromEntries(await Promise.all(Object.keys(EXPECT).map(async s => [s, Number((await rows(`SELECT count() AS n ${from(s)}`))[0].n)])));
let got = {};
for (let i = 0; i < 40; i++) {
  got = await counts();
  if (Object.keys(EXPECT).every(s => got[s] >= EXPECT[s])) break;
  await new Promise(r => setTimeout(r, 500));
}
await new Promise(r => setTimeout(r, 1000)); // anything extra would arrive now
assert.deepEqual(await counts(), EXPECT, 'row counts per stream');

// ---- agentguard_cim_event ----
const cim = await rows(`SELECT event_type, raw_hook_name, run_id, provider, model, tool_name, tool_input, tool_result, tool_duration_ms, ` +
  `user_message, assistant_message, to_unix_timestamp64_milli(event_time) AS ts ${from('agentguard_cim_event')} ORDER BY event_time, event_type`);
const count = (list, key) => list.reduce((m, r) => (m[key(r)] = (m[key(r)] || 0) + 1, m), {});
assert.deepEqual(count(cim, r => r.event_type + ' < ' + r.raw_hook_name), {
  'session_start < session_start': 1, 'session_start < subagent_start': 1, 'session_end < session_end': 1,
  'user_input < user_prompt_submit': 2, 'llm_response < stop': 1,
  'llm_request < post_model_request': 4, 'llm_response < post_model_request': 4,
  'tool_invoke < pre_tool_use': 4, 'tool_complete < post_tool_use': 4,
});
assert.ok(cim.every(r => r.model === 'gpt-5-codex' && r.provider === 'openai'), 'model and provider on every row');
assert.deepEqual(cim.filter(r => r.event_type === 'user_input').map(r => [r.user_message, r.run_id]), [['fix the failing test', 't1'], ['also run the linter', 't2']]);
assert.deepEqual(cim.filter(r => r.assistant_message).map(r => [r.event_type, r.assistant_message]), [['llm_response', 'Fixed.']]); // the sub-agent's "Found it." is not a reply
const done = cim.filter(r => r.event_type === 'tool_complete');
assert.deepEqual(done.map(r => r.tool_name), ['Bash', 'update_plan', 'Bash', 'Bash']);
assert.deepEqual(JSON.parse(done[0].tool_input), { command: 'cat /h/.codex/skills/.system/openai-docs/SKILL.md' }); // an object, not wrapped in an array
assert.deepEqual(JSON.parse(done[0].tool_result), { exit_code: 0, output: '# OpenAI docs' });
assert.equal(done[1].tool_result, 'Plan updated'); // a string result stays as it is
assert.ok(done.every(r => Number(r.tool_duration_ms) > 0), 'tool_duration_ms on tool_complete');
assert.ok(cim.filter(r => r.event_type === 'tool_invoke').every(r => r.tool_input && !r.tool_result && Number(r.tool_duration_ms) === 0));
const req = cim.filter(r => r.event_type === 'llm_request'), resp = cim.filter(r => r.event_type === 'llm_response' && r.raw_hook_name === 'post_model_request');
assert.ok(req.every((r, i) => Number(r.ts) < Number(resp[i].ts)), 'llm_request is stamped at the start of the model request');

// ---- agentguard_cim_metrics ----
const metrics = await rows(`SELECT agent_type, metric_name, metric_value, tags['run_id'] AS run_id, tags['model'] AS model, tags['tool_name'] AS tool ${from('agentguard_cim_metrics')} ORDER BY event_time, metric_name`);
// #72: the tool metric views of the other agents must not count a Codex tool call under their own type.
assert.deepEqual(count(metrics, m => m.agent_type), { codex: 33 }, 'every metric row of a Codex session is a codex row');
const sum = name => metrics.filter(m => m.metric_name === name).reduce((a, m) => a + Number(m.metric_value), 0);
assert.deepEqual(count(metrics, m => m.metric_name), { 'llm.call': 4, 'llm.total_tokens': 4, 'llm.input_tokens': 4, 'llm.output_tokens': 4,
  'llm.cache_read_tokens': 4, 'llm.latency_ms': 4, 'llm.cache_write_tokens': 1, 'tool.call': 4, 'tool.success': 4 });
assert.deepEqual(['llm.input_tokens', 'llm.output_tokens', 'llm.total_tokens', 'llm.cache_read_tokens', 'llm.cache_write_tokens'].map(sum), [3600, 450, 4050, 2300, 64]);
assert.ok(metrics.every(m => m.model === 'gpt-5-codex' && m.run_id === 't1'), 'model and run_id tags');
assert.ok(metrics.filter(m => m.metric_name === 'llm.latency_ms').every(m => Number(m.metric_value) > 0));

// ---- agentguard_skills ----
const skills = await rows(`SELECT skill_name, skill_action, skill_source_type, skill_location, agent_type, to_unix_timestamp64_milli(event_time) AS ts ${from('agentguard_skills')}`);
assert.deepEqual(skills.map(({ ts, ...r }) => r), [{ skill_name: 'openai-docs', skill_action: 'invoked', skill_source_type: 'system', skill_location: '/h/.codex/skills/.system/openai-docs/SKILL.md', agent_type: 'codex' }]);
assert.equal(skills[0].ts, cim.find(r => r.event_type === 'tool_invoke').ts, 'the skill row shares its timestamp with the tool_invoke row');

// ---- no second copy from the views that serve the OTel path ----
assert.equal(Number((await rows(`SELECT count() AS n ${from('agentguard_hook_events')}`))[0].n), fixture.data.length, 'nothing bridged back into agentguard_hook_events');

// ---- Agent Rooms: the page's own queries, read as history, fed to its session model ----
const page = async (sql, kind) => (await rows(sql.replace(/FROM (\w+\.\w+) WHERE/, 'FROM table($1) WHERE') + ` AND ${mine}`)).map(r => ({ ...r, kind }));
const feed = [...await page(eventsSQL(DB, 30), 'event'), ...await page(hooksSQL(DB, 30), 'hook'), ...await page(skillsSQL(DB, 30), 'skill'), ...await page(metricsSQL(DB, 30), 'metric')]
  .sort((a, b) => Number(a.ts) - Number(b.ts));
const st = new Store();
for (const r of feed) ({ event: () => st.event(r), hook: () => st.hook(r), skill: () => st.skill(r), metric: () => st.metric(r) })[r.kind]();
st.flush(Date.now() + 5000);
const s = st.sessions.get(SESSION);
assert.ok(s, 'the session has a room');
assert.deepEqual([s.badge, s.typeName, s.model, s.cwd, s.agentId], ['CX', 'Codex', 'gpt-5-codex', '/work/demo-repo', 'fixture-host']);
assert.deepEqual([s.prompt, s.reply, s.ended, s.calls, s.failures, s.open.size], ['also run the linter', 'Fixed.', true, 4, 0, 0]);
const sub = s.subs.get('agent_7');
assert.deepEqual([s.subs.size, sub.name, sub.ended, sub.cards], [1, 'explorer', true, 1]); // one tool call ran inside the sub-agent
assert.deepEqual([...s.skillsUsed], [['openai-docs', 1]]);
assert.deepEqual([...s.tasks.values()], [{ subject: 'Read the test', done: true }, { subject: 'Fix it', done: false }]);
assert.deepEqual([s.ctx, s.ctxReal], [2000, true]); // the last model request of the main agent: input tokens alone
const log = s.log.map(e => e.label);
for (const want of ['Load skill: openai-docs', 'Asked permission: Bash make test', 'Turn interrupted by the user', 'Fixed.'])
  assert.ok(log.includes(want), 'activity log has: ' + want);
assert.ok(log.some(l => l.startsWith('Compacted ')), 'activity log has the compaction');

console.log(`ok: Codex hook-event path, session ${SESSION}: ${cim.length} CIM rows, ${metrics.length} metric rows, ${skills.length} skill row, room checked`);
