// Pure mapping helpers: tool name -> room object, labels, agent badges, token estimates.

/** Room object kinds a tool call can be routed to. */
export const KINDS = ['files', 'shell', 'web', 'skill', 'memory', 'mcp', 'sub', 'other'];

const FILES = new Set(['read', 'write', 'edit', 'multiedit', 'grep', 'glob', 'ls', 'notebookedit', 'notebookread',
  'read_file', 'write_file', 'patch', 'search_files', 'apply_patch', 'list_files', 'find', 'lsp']);
const SHELL = new Set(['bash', 'bashoutput', 'killshell', 'exec', 'process', 'terminal', 'shell', 'execute_code', 'monitor']);
const WEB = new Set(['webfetch', 'websearch', 'web_fetch', 'web_search', 'web_extract', 'browser', 'browser_navigate']);
const SKILL = new Set(['skill', 'skill_view', 'skills_list', 'skill_manage']);
const SUB = new Set(['agent', 'task', 'delegate_task', 'sessions_spawn', 'subagent']);
const MEMORY = new Set(['memory', 'memory_search', 'memory_get', 'memory_write', 'save_memory', 'session_search']);
const MEMORY_PATH = /(^|\/)(memory|memories)\/|MEMORY\.md$|\/\.claude\/projects\/[^/]+\/memory/i;

/**
 * Map a tool call to the room object that represents it.
 * @param {string} tool tool name as reported by the agent
 * @param {string} [arg] primary argument (file path, command, ...) used to spot memory files
 */
export function toolKind(tool, arg = '') {
  const t = String(tool || '').toLowerCase();
  if (!t) return 'other';
  if (t.startsWith('mcp__') || t.startsWith('mcp_')) return /mem(ory)?[-_]|[-_]mem(ory)?|memory/.test(t) ? 'memory' : 'mcp';
  if (MEMORY.has(t) || t.startsWith('memory_')) return 'memory';
  if (FILES.has(t)) return MEMORY_PATH.test(arg) ? 'memory' : 'files';
  if (SHELL.has(t)) return 'shell';
  if (WEB.has(t) || t.startsWith('browser_')) return 'web';
  if (SKILL.has(t)) return 'skill';
  if (SUB.has(t)) return 'sub';
  return 'other';
}

const short = (s, n) => { s = String(s || '').replace(/\s+/g, ' ').trim(); return s.length > n ? s.slice(0, n - 1) + '…' : s; };
const tail = p => { const parts = String(p).split('/').filter(Boolean); return parts.length > 2 ? '…/' + parts.slice(-2).join('/') : String(p); };

/** Human label for a tool call, e.g. "Read …/auth/login.ts" or "github · create_pr". */
export function toolLabel(tool, arg = '') {
  const t = String(tool || 'tool');
  if (/^mcp__/i.test(t)) {
    const [, server = '', ...rest] = t.split('__');
    const name = rest.join('__');
    return short(server.replace(/^(plugin_|claude_ai_)/, '') + (name ? ' · ' + name : ''), 80);
  }
  if (!arg) return t;
  const a = /^(\/|~\/|\.\.?\/)\S*$/.test(arg) ? tail(arg) : arg;
  return short(t + ' ' + a, 80);
}

const AGENTS = { claudecode: ['CC', 'Claude Code'], openclaw: ['OC', 'OpenClaw'], hermes: ['HM', 'Hermes'] };
/** [badge, display name] for an agent_type value. */
export function agentInfo(agentType) {
  const a = String(agentType || '').toLowerCase();
  return AGENTS[a] || [(a.slice(0, 2) || 'AG').toUpperCase(), agentType || 'Agent'];
}

/** Rough token estimate from a payload size in characters (about 4 chars per token). */
// Tools whose whole purpose is to put a question to the user and wait for the answer.
const ASK_TOOL = /^(ask_?user(_?question)?|ask_?followup_?question|ask_?human|clarify)$/i;
export const isAskTool = tool => ASK_TOOL.test(String(tool || ''));

/**
 * Does a message the agent ended its turn with ask the user something? True when its last
 * line, ignoring closing quotes, brackets and markdown emphasis, ends in a question mark.
 */
export function isQuestion(text) {
  const lines = String(text || '').split('\n').map(l => l.trim()).filter(Boolean);
  return lines.length > 0 && /[?？]$/.test(lines[lines.length - 1].replace(/[\s"'”’)\]*_`]+$/, ''));
}

export function estTokens(chars) { return Math.max(20, Math.ceil((Number(chars) || 0) / 4)); }

/** Short room name from working directory + session id. */
export function sessionName(sessionId, cwd = '', agentId = '') {
  const id = String(sessionId || '').slice(0, 8);
  const base = String(cwd || '').split('/').filter(Boolean).pop() || String(agentId || '').replace(/\.local$/, '');
  return base ? short(base, 22) + ' · ' + id : id || 'session';
}
