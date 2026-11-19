import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readContext } from '../../web/agent-rooms/src/context.js';
import { queryURL } from '../../web/agent-rooms/src/timeplus.js';

const PATH = '/acme/apps/io.timeplus.agentguard/ui/agent-rooms/';

test('reads the context the console appends to the entry URL', () => {
  assert.deepEqual(readContext('?workspace=acme&app_id=io.timeplus.agentguard&db=guard&theme=light', PATH),
    { workspace: 'acme', appId: 'io.timeplus.agentguard', db: 'guard', theme: 'light', minutes: 30 });
});
test('falls back to the serve path and defaults when opened without parameters', () => {
  assert.deepEqual(readContext('', PATH), { workspace: 'acme', appId: 'io.timeplus.agentguard', db: 'ag', theme: 'dark', minutes: 30 });
  assert.deepEqual(readContext('', '/index.html'), { workspace: 'default', appId: '', db: 'ag', theme: 'dark', minutes: 30 });
});
test('rejects a database name that is not an identifier and an unknown theme', () => {
  const c = readContext('?db=ag;DROP&theme=neon', PATH);
  assert.equal(c.db, 'ag'); assert.equal(c.theme, 'dark');
});
test('look-back comes from the URL, then the saved choice, within 1 to 1440 minutes', () => {
  assert.equal(readContext('?minutes=5', PATH, '60').minutes, 5);
  assert.equal(readContext('', PATH, '60').minutes, 60);
  assert.equal(readContext('?minutes=99999', PATH).minutes, 30);
});
test('queries go to the same origin, in the workspace from the context', () => {
  assert.equal(queryURL({ workspace: 'acme' }), '/acme/api/v1beta2/queries');
  assert.equal(queryURL({ workspace: 'a b' }), '/a%20b/api/v1beta2/queries');
});
