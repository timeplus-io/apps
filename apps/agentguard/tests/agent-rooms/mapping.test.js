import { test } from 'node:test';
import assert from 'node:assert/strict';
import { toolKind, toolLabel, agentInfo, estTokens, sessionName } from '../../web/agent-rooms/src/mapping.js';

test('tool families map to room objects', () => {
  const cases = { Bash: 'shell', Read: 'files', Edit: 'files', Grep: 'files', Glob: 'files', WebFetch: 'web', WebSearch: 'web', Skill: 'skill',
    Agent: 'sub', Task: 'sub', mcp__github__create_pr: 'mcp', 'mcp__plugin_claude-mem_mcp-search__search': 'memory', TodoWrite: 'other',
    exec: 'shell', terminal: 'shell', read_file: 'files', web_search: 'web', memory_search: 'memory', delegate_task: 'sub', '': 'other' };
  for (const [tool, kind] of Object.entries(cases)) assert.equal(toolKind(tool), kind, tool);
});
test('reading a memory file counts as memory', () => {
  assert.equal(toolKind('Read', '/Users/x/.claude/projects/p/memory/MEMORY.md'), 'memory');
  assert.equal(toolKind('Read', '/repo/src/memory.ts'), 'files');
});
test('labels are short and readable', () => {
  assert.equal(toolLabel('Read', '/a/b/c/src/auth/login.ts'), 'Read …/auth/login.ts');
  assert.equal(toolLabel('Bash', 'pnpm test'), 'Bash pnpm test');
  assert.equal(toolLabel('mcp__github__create_pr'), 'github · create_pr');
  assert.equal(toolLabel('TodoWrite'), 'TodoWrite');
  assert.ok(toolLabel('Bash', 'x'.repeat(300)).length <= 80);
});
test('agent badges, token estimate, session name', () => {
  assert.deepEqual(agentInfo('claudecode'), ['CC', 'Claude Code']);
  assert.deepEqual(agentInfo('hermes'), ['HM', 'Hermes']);
  assert.equal(agentInfo('custom')[0], 'CU');
  assert.equal(estTokens(4000), 1000); assert.equal(estTokens(0), 20);
  assert.equal(sessionName('1ffd9504-3100', '/Users/x/Code/AgentGuard'), 'AgentGuard · 1ffd9504');
  assert.equal(sessionName('1ffd9504-3100', '', 'host.local'), 'host · 1ffd9504');
});
