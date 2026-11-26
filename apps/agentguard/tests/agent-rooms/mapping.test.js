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

// Codex (timeplus-io/apps#69)
import { isReadCommand, patchPath, planSteps } from '../../web/agent-rooms/src/mapping.js';
test('Codex tool names map to room objects', () => {
  const cases = { webrun: 'web', spawn_agent: 'sub', update_plan: 'other', mcp__github__create_pr: 'mcp' };
  for (const [tool, kind] of Object.entries(cases)) assert.equal(toolKind(tool, '', 'codex'), kind, tool);
  assert.deepEqual(agentInfo('codex'), ['CX', 'Codex']);
});
test('a Codex shell command that only reads goes to the files, any other to the terminal', () => {
  for (const c of ['cat src/a.py', 'rg --files -g "!.git" | head -180', 'sed -n 1,80p README.md', 'ls -d .codex/hooks.json 2>/dev/null', 'find . -name "*.md"'])
    assert.equal(toolKind('Bash', c, 'codex'), 'files', c);
  for (const c of ['git remote -v', 'python3 -B - <<PY', 'sed -i s/a/b/ x.txt', 'cat a.txt > b.txt', 'echo hi >> log', 'pnpm test'])
    assert.equal(toolKind('Bash', c, 'codex'), 'shell', c);
  assert.equal(toolKind('Bash', 'cat src/a.py', 'claudecode'), 'shell'); // agents with a Read tool keep the shell as the shell
  assert.equal(toolKind('Bash', 'cat src/a.py'), 'shell');
  assert.equal(toolKind('Bash', 'cat /h/.codex/skills/.system/openai-docs/SKILL.md', 'codex'), 'skill'); // reading a skill is using it
  assert.equal(toolKind('Bash', 'sed -n 1,40p /h/.codex/memories/MEMORY.md', 'codex'), 'memory');
  assert.equal(isReadCommand('  ls'), true); assert.equal(isReadCommand('lsof -i'), false);
});
test('apply_patch is labelled with the file it touches', () => {
  const patch = '*** Begin Patch\n*** Add File: /w/repo/docs/notes/issue.md\n+hello\n*** End Patch';
  assert.equal(patchPath(patch), '/w/repo/docs/notes/issue.md'); assert.equal(patchPath('no header'), '');
  assert.equal(toolLabel('apply_patch', patch), 'apply_patch …/notes/issue.md');
  assert.equal(toolKind('apply_patch', patch, 'codex'), 'files');
  assert.equal(toolKind('apply_patch', '*** Begin Patch\n*** Update File: /h/.codex/memories/MEMORY.md\n', 'codex'), 'memory');
  assert.ok(toolLabel('apply_patch', 'garbage '.repeat(40)).length <= 80);
});
test('a plan tool call gives the steps of the plan', () => {
  const plan = { explanation: 'x', plan: [{ step: 'Read the code', status: 'completed' }, { step: 'Fix it', status: 'in_progress' }, { step: 'Test', status: 'pending' }] };
  const want = [{ subject: 'Read the code', done: true }, { subject: 'Fix it', done: false }, { subject: 'Test', done: false }];
  assert.deepEqual(planSteps(JSON.stringify(plan)), want);
  assert.deepEqual(planSteps(JSON.stringify([plan])), want);
  for (const bad of ['', '{"plan": [{"step": "cut sho', '{"plan": "no"}', '{"command": "ls"}', 'null']) assert.deepEqual(planSteps(bad), []);
});
