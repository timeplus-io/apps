import { test } from 'node:test';
import assert from 'node:assert/strict';
import { SSEParser, RowDecoder } from '../../web/agent-rooms/src/sse.js';
import { eventsSQL, metricsSQL, hooksSQL, skillsSQL, memorySQL, since } from '../../web/agent-rooms/src/queries.js';

test('parses events split across chunks and decodes rows by header', () => {
  const p = new SSEParser(), d = new RowDecoder(), rows = [];
  const text = 'event: query\ndata: {"status":"running","result":{"header":[{"name":"ts","type":"int64"},{"name":"tool_name","type":"string"}]}}\n\n' +
    'data: [[1,"Read"],[2,"Bash"]]\n\nevent: metrics\ndata: {"count":2}\n\ndata: [[3,"Grep"]]\n\n';
  for (let i = 0; i < text.length; i += 7) for (const ev of p.feed(text.slice(i, i + 7))) rows.push(...d.push(ev));
  assert.deepEqual(rows, [{ ts: 1, tool_name: 'Read' }, { ts: 2, tool_name: 'Bash' }, { ts: 3, tool_name: 'Grep' }]);
});
test('reports a failed query', () => {
  const d = new RowDecoder();
  d.push({ event: 'query', data: '{"status":"failed","message":"boom"}' });
  assert.equal(d.status, 'failed'); assert.equal(d.message, 'boom');
});
test('queries target the app streams and reject bad database names', () => {
  assert.match(eventsSQL('ag', 30), /FROM ag\.agentguard_cim_event WHERE .*_tp_time > now\(\) - 30m$/);
  assert.match(metricsSQL('ag', 30), /FROM ag\.agentguard_cim_metrics/);
  assert.match(hooksSQL('ag', 30), /FROM ag\.agentguard_hook_events/);
  assert.match(skillsSQL('ag', 30), /FROM ag\.agentguard_skills/); assert.match(memorySQL('ag', 30), /FROM ag\.agentguard_memory_ops/);
  assert.throws(() => eventsSQL('ag; drop', 30));
  assert.equal(since(30, 1795040907091), "_tp_time > to_datetime64(1795040907.091, 3, 'UTC')");
  assert.equal(since(99999), '_tp_time > now() - 1440m');
});
