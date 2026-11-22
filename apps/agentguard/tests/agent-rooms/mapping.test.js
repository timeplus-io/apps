import { test } from 'node:test';
import assert from 'node:assert/strict';
import { toolKind, toolLabel, agentInfo, estTokens, sessionName } from '../../web/agent-rooms/src/mapping.js';
import { isAskTool, isQuestion } from '../../web/agent-rooms/src/mapping.js';
import { arrow, META } from '../../web/agent-rooms/src/icons.js';

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

test('a message is a question when its last line ends in a question mark', () => {
  for (const t of ['Apply it now?', 'Two options.\n\nWhich do you prefer?\n', 'Should I continue?**', 'Proceed? "', '要继续吗？', 'Done. (Or should I also update the docs?)'])
    assert.equal(isQuestion(t), true, t);
  for (const t of ['', null, 'Done.', 'Why did it fail? A stale cookie.', 'What changed?\n- login.ts\n- session.ts'])
    assert.equal(isQuestion(t), false, String(t));
});
test('ask-the-user tools are recognised by name', () => {
  for (const t of ['AskUserQuestion', 'ask_user', 'ask_followup_question', 'clarify', 'AskHuman']) assert.equal(isAskTool(t), true, t);
  for (const t of ['Bash', 'Task', 'ask', '', undefined, 'mcp__slack__ask_user']) assert.equal(isAskTool(t), false, String(t));
});
test('history entries are marked by direction', () => {
  assert.equal(arrow({ kind: 'phone', dir: 'in' }), '↓ '); assert.equal(arrow({ kind: 'phone' }), '↓ ');
  assert.equal(arrow({ kind: 'phone', dir: 'out' }), '↑ '); assert.equal(arrow({ kind: 'note' }), '· '); assert.equal(arrow({ kind: 'files' }), '');
  assert.equal(META.phone[0], 'User'); assert.ok(META.reply && META.note);
});
