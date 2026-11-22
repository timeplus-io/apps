import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readMinutes } from '../../web/agent-rooms/src/context.js';
import { queryURL } from '../../web/agent-rooms/src/timeplus.js';

test('look-back comes from the URL, then the saved choice, within 1 to 1440 minutes', () => {
  assert.equal(readMinutes('?minutes=5', '60'), 5);
  assert.equal(readMinutes('', '60'), 60);
  assert.equal(readMinutes(''), 30);
  assert.equal(readMinutes('?minutes=99999'), 30);
  assert.equal(readMinutes('?minutes=abc', '0'), 30);
});
test('queries go to the same origin, in the workspace from the context', () => {
  assert.equal(queryURL({ workspace: 'acme' }), '/acme/api/v1beta2/queries');
  assert.equal(queryURL({ workspace: 'a b' }), '/a%20b/api/v1beta2/queries');
});
