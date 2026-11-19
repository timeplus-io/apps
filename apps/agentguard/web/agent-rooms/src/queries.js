// SQL for the three streaming queries that drive the view. Everything on screen comes from these.

const ident = (s, what) => { if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(String(s))) throw new Error('Invalid ' + what + ': ' + s); return s; };

/** WHERE fragment: backfill from `sinceMs` (epoch ms) if given, else from `minutes` ago, then keep streaming. */
export function since(minutes, sinceMs) {
  if (sinceMs) return `_tp_time > to_datetime64(${(Number(sinceMs) / 1000).toFixed(3)}, 3, 'UTC')`;
  const m = Math.max(1, Math.min(1440, Math.round(Number(minutes) || 30)));
  return `_tp_time > now() - ${m}m`;
}

// tool_input keys that best describe a call, in priority order.
export const ARG_KEYS = ['command', 'file_path', 'notebook_path', 'pattern', 'url', 'query', 'skill', 'subagent_type', 'description', 'path', 'name', 'prompt'];
// json_query() returns the object wrapped in an array ('[{...}]') on current Timeplus, so try both shapes.
const jv = (col, k) => `if(json_value(${col}, '$.${k}') != '', json_value(${col}, '$.${k}'), json_value(${col}, '$[0].${k}'))`;
const firstArg = col => 'multi_if(' + ARG_KEYS.map(k => `${jv(col, k)} != '', ${jv(col, k)}`).join(', ') + `, '')`;

/** Normalized lifecycle events: sessions, prompts, tool calls, answers. */
export function eventsSQL(db, minutes, sinceMs) {
  return `SELECT to_unix_timestamp64_milli(event_time) AS ts, event_type, agent_type, agent_id, session_id, model, tool_name, ` +
    `substring(${firstArg('tool_input')}, 1, 240) AS tool_arg, ` +
    `${jv('tool_input', 'subagent_type')} AS sub_type, ` +
    `length(tool_input) + length(tool_result) AS payload_chars, tool_success, tool_duration_ms, hook_decision, ` +
    `substring(user_message, 1, 2000) AS user_message, length(user_message) AS user_chars, ` +
    `substring(assistant_message, 1, 600) AS assistant_message, raw_hook_name, ` +
    `json_value(raw_event_data, '$.cwd') AS cwd, json_value(raw_event_data, '$.source') AS source, json_value(raw_event_data, '$.tool_use_id') AS call_id, ` +
    `json_value(raw_event_data, '$.agent_id') AS sub_id, json_value(raw_event_data, '$.agent_type') AS sub_name ` +
    `FROM ${ident(db, 'database')}.agentguard_cim_event ` +
    `WHERE event_type IN ('session_start', 'session_end', 'user_input', 'llm_response', 'tool_invoke', 'tool_complete') AND ${since(minutes, sinceMs)}`;
}

/** Per-LLM-call token metrics: the real context size. */
export function metricsSQL(db, minutes, sinceMs) {
  return `SELECT to_unix_timestamp64_milli(event_time) AS ts, session_id, metric_name, metric_value, tags['model'] AS model ` +
    `FROM ${ident(db, 'database')}.agentguard_cim_metrics ` +
    `WHERE metric_name IN ('llm.input_tokens', 'llm.cache_read_tokens', 'llm.cache_write_tokens') AND ${since(minutes, sinceMs)}`;
}

/** Raw hooks the CIM views do not carry: sub-agent stop, tool failures, permission denials, instruction files loaded, compaction. */
export function hooksSQL(db, minutes, sinceMs) {
  return `SELECT to_unix_timestamp64_milli(event_time) AS ts, session_id, hook_name, agent_type, ` +
    `if(tool_name != '', tool_name, json_value(event_data, '$.tool_name')) AS tool_name, ` +
    `substring(${firstArg(`json_query(event_data, '$.tool_input')`)}, 1, 240) AS tool_arg, ` +
    `substring(json_value(event_data, '$.error'), 1, 300) AS error, json_value(event_data, '$.tool_use_id') AS call_id, ` +
    `json_value(event_data, '$.agent_id') AS sub_id, json_value(event_data, '$.file_path') AS file_path, ` +
    `json_value(event_data, '$.memory_type') AS memory_type, json_value(event_data, '$.load_reason') AS load_reason, ` +
    `json_value(event_data, '$.trigger') AS compact_trigger, json_value(event_data, '$.task_id') AS task_id, ` +
    `substring(json_value(event_data, '$.task_subject'), 1, 200) AS task_subject ` +
    `FROM ${ident(db, 'database')}.agentguard_hook_events ` +
    `WHERE hook_name IN ('subagent_ended', 'tool_call_failure', 'permission_denied', 'instructions_loaded', 'pre_compact', 'post_compact', 'task_created', 'task_completed', 'stop_failure') AND ${since(minutes, sinceMs)}`;
}

/** Skill events the app extracts (invoked through the Skill tool, or listed as available in a prompt). */
export function skillsSQL(db, minutes, sinceMs) {
  return `SELECT to_unix_timestamp64_milli(event_time) AS ts, session_id, skill_name, skill_action, skill_namespace, skill_source_type ` +
    `FROM ${ident(db, 'database')}.agentguard_skills WHERE skill_name != '' AND ${since(minutes, sinceMs)}`;
}

/** Memory operations the app extracts (memory MCP servers and memory files). */
export function memorySQL(db, minutes, sinceMs) {
  return `SELECT to_unix_timestamp64_milli(event_time) AS ts, session_id, memory_source, memory_op, tool_name, server_name, memory_path, ` +
    `length(content_payload) AS payload_chars ` +
    `FROM ${ident(db, 'database')}.agentguard_memory_ops WHERE ${since(minutes, sinceMs)}`;
}
