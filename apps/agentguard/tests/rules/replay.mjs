// Live check of the detection rules (timeplus-io/apps#86). Needs a Timeplus with this app installed.
//
// cases.json holds benign and risky tool calls, tool results and prompts with the rules each one must
// raise. This script writes every case to agentguard_cim_event, the stream the rule views read, as
// a row shaped the way the CIM views shape it (a Claude Code tool input is wrapped in an array, a
// Codex one is not; shell cases are written both ways), waits, and compares the rules that fired
// with the expected ones. A benign case that raises a rule fails the test as much as a missed one.
// Nothing in a case is executed, and the secrets are fakes assembled below.
//
//   TIMEPLUS_URL=http://localhost:8123 TIMEPLUS_USER=... TIMEPLUS_PASSWORD=... make test-rules
//
// It leaves its rows (and the detections and threats they raise) in the target, under session ids
// that start with `rules-`. Run it against a development instance.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const URL_ = (process.env.TIMEPLUS_URL || 'http://localhost:8123').replace(/\/$/, '');
const DB = process.env.TIMEPLUS_DB || 'ag';
const USER = process.env.TIMEPLUS_USER || 'default', PASSWORD = process.env.TIMEPLUS_PASSWORD || '';
const TAG = 'rules-' + Date.now().toString(36);

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

// Fake secrets in the shape of real ones, put together here so that the repository holds none.
const FAKE = {
  '<GHP>': 'ghp' + '_' + 'SIMfake0'.repeat(4) + 'ABCD',
  '<ANT>': 'sk-' + 'ant-' + 'api03-' + 'SIMULATEDfake' + '0'.repeat(22),
  '<AKIA>': 'AKIA' + 'SIMFAKE0SIMFAKE0',
  '<JWT>': ['eyJ' + 'hbGciOiJIUzI1NiJ9', 'eyJ' + 'zdWIiOiJzaW11bGF0ZWQifQ', 'c2ltdWxhdGVkc2lnbmF0dXJl'].join('.'),
};
const fill = s => Object.entries(FAKE).reduce((t, [k, v]) => t.replaceAll(k, v), s);

const { cases } = JSON.parse(fill(readFileSync(new URL('./cases.json', import.meta.url), 'utf8')));
const COLS = ['event_time', 'event_type', 'agent_type', 'agent_id', 'deployment_id', 'session_id', 'run_id', 'tool_name', 'tool_input', 'tool_result', 'user_message', 'raw_hook_name', 'raw_event_data'];
let clock = Date.now() - 60000;
const stamp = () => new Date(clock += 10).toISOString().replace('T', ' ').replace('Z', '');
const out = [], expected = new Map();
function add(session, want, agent, type, tool, input, result, prompt) {
  expected.set(session, want);
  out.push(JSON.stringify([stamp(), type, agent, 'rules-test', 'test', session, 'r1', tool, input, result, prompt, type, '{}']));
}
for (const c of cases) {
  if (c.prompt !== undefined) { add(`${TAG}-${c.id}`, c.expect, 'claudecode', 'user_input', '', '', '', c.prompt); continue; }
  const shapes = c.command !== undefined
    ? [['cc', 'claudecode', 'Bash', JSON.stringify([{ command: c.command }])], ['cx', 'codex', 'Bash', JSON.stringify({ command: c.command })]]
    : [['cc', 'claudecode', c.tool, JSON.stringify([c.input])]];
  for (const [suffix, agent, tool, input] of shapes) {
    const session = `${TAG}-${c.id}-${suffix}`;
    add(session, c.expect, agent, 'tool_invoke', tool, input, '', '');
    if (c.result !== undefined) add(session, c.expect, agent, 'tool_complete', tool, input, c.result, '');
  }
}
await post(`INSERT INTO ${DB}.agentguard_cim_event (${COLS.join(', ')}) FORMAT JSONCompactEachRow`, out.join('\n'));

// ---- wait until every expected rule has fired, then a little longer for anything unexpected ----
const fired = async () => {
  const got = new Map([...expected.keys()].map(s => [s, new Set()]));
  for (const r of await rows(`SELECT session_id, rule_id FROM table(${DB}.agentguard_security_events) WHERE session_id LIKE '${TAG}-%'`)) got.get(r.session_id)?.add(r.rule_id);
  return got;
};
const complete = got => [...expected].every(([s, want]) => want.every(r => got.get(s).has(r)));
let got = await fired();
for (let i = 0; i < 40 && !complete(got); i++) { await new Promise(r => setTimeout(r, 500)); got = await fired(); }
await new Promise(r => setTimeout(r, 1500));
got = await fired();

const wrong = [];
for (const [session, want] of expected) {
  const have = [...got.get(session)].sort(), need = [...want].sort();
  if (have.join() !== need.join()) wrong.push(`${session.slice(TAG.length + 1)}: expected [${need}] got [${have}]`);
}
assert.deepEqual(wrong, [], 'rules fired per case');

// ---- a detection never repeats the secret it found ----
const messages = await rows(`SELECT rule_id, message FROM table(${DB}.agentguard_security_events) WHERE session_id LIKE '${TAG}-%'`);
for (const m of messages) for (const secret of [...Object.values(FAKE), 'S1mulatedPw9', 'Hunter2!x', 'SIMfakeBearerToken0123456789abcdef'])
  assert.ok(!m.message.includes(secret), `the message of ${m.rule_id} repeats a secret: ${m.message}`);
assert.ok(messages.every(m => m.message.length > 0 && !m.message.endsWith(': ')), 'every detection says what it found');

// ---- threats: every rule but the low and info ones ----
const QUIET = ['supply.install', 'inject.prompt'];
const wantThreats = new Set([...expected].flatMap(([s, want]) => want.filter(r => !QUIET.includes(r)).map(r => s + ' ' + r)));
let threats = new Set();
for (let i = 0; i < 20; i++) {
  threats = new Set((await rows(`SELECT session_id, rule_id FROM table(${DB}.agentguard_threats) WHERE session_id LIKE '${TAG}-%'`)).map(t => t.session_id + ' ' + t.rule_id));
  if (threats.size >= wantThreats.size) break;
  await new Promise(r => setTimeout(r, 500));
}
assert.deepEqual([...threats].sort(), [...wantThreats].sort(), 'threats: one per session and rule, none for low or info rules');

console.log(`ok: ${cases.length} cases (${expected.size} sessions, ${out.length} rows): ${messages.length} detections, ${threats.size} threats, as expected`);
