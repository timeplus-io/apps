// Live check of what the CIM views make of failed tool calls, permission waits and Claude Code model
// requests (timeplus-io/apps#75, #76; timeplus-io/AgentGuard#324). Needs a Timeplus with this app installed.
//
// It writes a handful of hook rows, shaped as the Claude Code plugin 0.7.1 and the Codex plugin 0.3.0
// send them, to agentguard_hook_events under new session ids, waits for the views, and checks the
// rows in agentguard_cim_event and agentguard_cim_metrics.
//
//   TIMEPLUS_URL=http://localhost:8123 TIMEPLUS_USER=... TIMEPLUS_PASSWORD=... make test-hook-events
import assert from 'node:assert/strict';

const URL_ = (process.env.TIMEPLUS_URL || 'http://localhost:8123').replace(/\/$/, '');
const DB = process.env.TIMEPLUS_DB || 'ag';
const USER = process.env.TIMEPLUS_USER || 'default', PASSWORD = process.env.TIMEPLUS_PASSWORD || '';
const TAG = Date.now().toString(36), CC = 'hook-events-cc-' + TAG, CX = 'hook-events-cx-' + TAG;

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

// ---- the hook rows ----
let clock = Date.now() - 20000;
const stamp = () => new Date(clock += 1000).toISOString().replace('T', ' ').replace('Z', '');
const COLS = ['hook_name', 'event_time', 'session_id', 'run_id', 'agent_id', 'deployment_id', 'tool_name', 'provider', 'model', 'hook_decision', 'event_data', 'agent_type'];
const cc = (hook, data, extra = {}) => [hook, stamp(), CC, data.prompt_id || CC, 'fixture-host', 'local', extra.tool || '', extra.provider || '', extra.model || '', 'observe',
  JSON.stringify({ session_id: CC, cwd: '/work/demo-repo', ...data }), 'claudecode'];
const cx = (hook, data, tool = '') => [hook, stamp(), CX, 't1', 'fixture-host', 'local', tool, 'openai', 'gpt-5-codex', 'observe',
  JSON.stringify({ session_id: CX, turn_id: 't1', cwd: '/work/demo-repo', model: 'gpt-5-codex', ...data, 'agentguard.export': 'hooks' }), 'codex'];
const usage = (input, output, read, write) => ({ input_tokens: input, output_tokens: output, cache_read_input_tokens: read, cache_creation_input_tokens: write, total_tokens: input + output });
const lines = [
  // Claude Code: a call that works, a call that fails, a permission wait, a denial, an idle notification
  cc('before_tool_call', { prompt_id: 'p1', hook_event_name: 'PreToolUse', tool_name: 'Bash', tool_input: { command: 'ls' }, tool_use_id: 'u1' }, { tool: 'Bash' }),
  cc('after_tool_call', { prompt_id: 'p1', hook_event_name: 'PostToolUse', tool_name: 'Bash', tool_input: { command: 'ls' }, tool_use_id: 'u1', duration_ms: 120,
    tool_response: { stdout: 'a\nb', stderr: '', interrupted: false } }, { tool: 'Bash' }),
  cc('before_tool_call', { prompt_id: 'p1', hook_event_name: 'PreToolUse', tool_name: 'Bash', tool_input: { command: 'make test' }, tool_use_id: 'u2' }, { tool: 'Bash' }),
  cc('tool_call_failure', { prompt_id: 'p1', hook_event_name: 'PostToolUseFailure', tool_name: 'Bash', tool_input: { command: 'make test' }, tool_use_id: 'u2', duration_ms: 745,
    error: 'Exit code 1\n2 tests failed', is_interrupt: false }, { tool: 'Bash' }),
  cc('permission_request', { prompt_id: 'p1', hook_event_name: 'PermissionRequest', tool_name: 'Write', tool_input: { file_path: '/work/demo-repo/a.txt', content: 'x' } }, { tool: 'Write' }),
  cc('permission_denied', { prompt_id: 'p1', hook_event_name: 'PermissionDenied', tool_name: 'Write', tool_input: { file_path: '/work/demo-repo/a.txt', content: 'x' }, reason: 'user said no' }, { tool: 'Write' }),
  cc('notification', { prompt_id: 'p1', hook_event_name: 'Notification', message: 'Claude is waiting for your input', notification_type: 'idle_prompt' }),
  // Claude Code: two model requests of the main agent, one of a sub-agent without a duration
  cc('llm_call', { prompt_id: 'p1', message_id: 'm1', model: 'claude-sonnet-4-6', stop_reason: 'tool_use', usage: usage(12, 538, 91230, 400), duration_ms: 6354, is_sidechain: false }, { model: 'claude-sonnet-4-6', provider: 'anthropic' }),
  cc('llm_call', { prompt_id: 'p1', message_id: 'm2', model: 'claude-sonnet-4-6', stop_reason: 'end_turn', usage: usage(5, 60, 92000, 0), duration_ms: 1500, is_sidechain: false }, { model: 'claude-sonnet-4-6', provider: 'anthropic' }),
  cc('llm_call', { prompt_id: 'p1', message_id: 'm3', model: 'claude-haiku-4-5', stop_reason: 'end_turn', usage: usage(100, 20, 0, 0), is_sidechain: true, subagent_id: 'a1' }, { model: 'claude-haiku-4-5', provider: 'anthropic' }),
  // Codex: a permission wait, an MCP call that returns an error, a shell call that exits 1
  cx('permission_request', { hook_event_name: 'PermissionRequest', tool_name: 'Bash', tool_input: { command: 'rm -rf build' } }, 'Bash'),
  cx('post_tool_use', { hook_event_name: 'PostToolUse', tool_name: 'mcp__repl__js', tool_input: { code: 'x(' }, tool_use_id: 'c1',
    tool_response: { content: [{ type: 'text', text: 'SyntaxError' }], isError: true }, 'agentguard.duration_ms': 40 }, 'mcp__repl__js'),
  cx('post_tool_use', { hook_event_name: 'PostToolUse', tool_name: 'Bash', tool_input: { command: 'false' }, tool_use_id: 'c2', tool_response: 'exit 1', 'agentguard.duration_ms': 15 }, 'Bash'),
].map(r => JSON.stringify(r));
await post(`INSERT INTO ${DB}.agentguard_hook_events (${COLS.join(', ')}) FORMAT JSONCompactEachRow`, lines.join('\n'));

// ---- wait for the views ----
const mine = `session_id IN ('${CC}', '${CX}')`;
// metrics: 3 model requests x 6 llm metrics + 2 latency rows, and tool.call + tool.success for each of the 4 finished tool calls
const EXPECT = { agentguard_cim_event: 10, agentguard_cim_metrics: 3 * 6 + 2 + 4 * 2 };
const counts = async () => Object.fromEntries(await Promise.all(Object.keys(EXPECT).map(async s => [s, Number((await rows(`SELECT count() AS n FROM table(${DB}.${s}) WHERE ${mine}`))[0].n)])));
for (let i = 0; i < 40; i++) {
  const got = await counts();
  if (Object.keys(EXPECT).every(s => got[s] >= EXPECT[s])) break;
  await new Promise(r => setTimeout(r, 500));
}
await new Promise(r => setTimeout(r, 1000)); // anything extra would arrive now
assert.deepEqual(await counts(), EXPECT, 'row counts per stream');

// ---- agentguard_cim_event ----
const cim = await rows(`SELECT agent_type, event_type, raw_hook_name, run_id, tool_name, tool_input, tool_result, tool_success, tool_duration_ms, block_reason, ` +
  `json_value(raw_event_data, '$.notification_type') AS notification_type FROM table(${DB}.agentguard_cim_event) WHERE ${mine} ORDER BY event_time`);
const of = (agent, hook) => cim.filter(r => r.agent_type === agent && r.raw_hook_name === hook);
const ok = r => r.tool_success === true || r.tool_success === 1;

// #75 Claude Code: a failed call has a tool_complete row, marked failed, with the error and the duration
const [worked] = of('claudecode', 'after_tool_call'), [failed] = of('claudecode', 'tool_call_failure');
assert.deepEqual([worked.event_type, ok(worked), Number(worked.tool_duration_ms)], ['tool_complete', true, 120]);
assert.deepEqual([failed.event_type, ok(failed), Number(failed.tool_duration_ms), failed.tool_name, failed.tool_result], ['tool_complete', false, 745, 'Bash', 'Exit code 1\n2 tests failed']);
assert.equal(JSON.parse(failed.tool_input)[0].command, 'make test', 'the failed call keeps its input');
// #75 Codex: an MCP error response is a failed call; a shell call counts as a success whatever its exit status
const [mcp, shell] = of('codex', 'post_tool_use');
assert.deepEqual([mcp.tool_name, ok(mcp), shell.tool_name, ok(shell)], ['mcp__repl__js', false, 'Bash', true]);

// #76: permission requests, denials and notifications are CIM rows of their own type
const [ask] = of('claudecode', 'permission_request'), [denied] = of('claudecode', 'permission_denied'), [note] = of('claudecode', 'notification'), [cxAsk] = of('codex', 'permission_request');
assert.deepEqual([ask.event_type, ask.tool_name, ask.run_id], ['permission_request', 'Write', 'p1']);
assert.deepEqual([denied.event_type, denied.tool_name, denied.block_reason], ['permission_denied', 'Write', 'user said no']);
assert.deepEqual([note.event_type, note.notification_type, note.tool_name], ['notification', 'idle_prompt', '']);
assert.deepEqual([cxAsk.event_type, cxAsk.tool_name, JSON.parse(cxAsk.tool_input).command, cxAsk.run_id], ['permission_request', 'Bash', 'rm -rf build', 't1']);
assert.deepEqual(cim.filter(r => !['tool_invoke', 'tool_complete', 'permission_request', 'permission_denied', 'notification'].includes(r.event_type)), [], 'no other event type');

// ---- agentguard_cim_metrics ----
const metrics = await rows(`SELECT agent_type, metric_name, metric_value, tags['model'] AS model, tags['run_id'] AS run_id, tags['sidechain'] AS sidechain ` +
  `FROM table(${DB}.agentguard_cim_metrics) WHERE ${mine}`);
const sum = (agent, name, pick = () => true) => metrics.filter(m => m.agent_type === agent && m.metric_name === name && pick(m)).reduce((a, m) => a + Number(m.metric_value), 0);
// the failed calls count as calls, not as successes
assert.deepEqual([sum('claudecode', 'tool.call'), sum('claudecode', 'tool.success'), sum('codex', 'tool.call'), sum('codex', 'tool.success')], [2, 1, 2, 1]);
// AgentGuard#324: one llm.call per model request, with the token counts of the Anthropic API
assert.deepEqual(['llm.call', 'llm.input_tokens', 'llm.output_tokens', 'llm.total_tokens', 'llm.cache_read_tokens', 'llm.cache_write_tokens'].map(n => sum('claudecode', n)),
  [3, 117, 618, 735, 183230, 400]);
assert.deepEqual([sum('claudecode', 'llm.latency_ms'), metrics.filter(m => m.metric_name === 'llm.latency_ms').length], [7854, 2], 'no latency row for a request without a duration');
assert.equal(sum('claudecode', 'llm.call', m => m.sidechain === 'true' && m.model === 'claude-haiku-4-5'), 1, 'the sub-agent request is tagged');
assert.ok(metrics.filter(m => m.metric_name.startsWith('llm.')).every(m => m.agent_type === 'claudecode' && m.run_id === 'p1'), 'llm metrics carry the turn as run_id');

console.log(`ok: failed tool calls, permission waits and Claude Code model requests: ${cim.length} CIM rows, ${metrics.length} metric rows (sessions ${CC}, ${CX})`);
