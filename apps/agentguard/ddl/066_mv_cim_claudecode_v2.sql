-- Replaces mv_cim_claudecode (#74), which wrote 0 as `tool_duration_ms`. Claude Code reports the
-- duration of a tool call as `duration_ms` in the PostToolUse payload, so `tool_complete` rows now
-- carry it. Everything else is as before. It reads from now on, so an upgrade does not write the
-- stored rows again.
CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_cim_claudecode_v2
INTO {{ .DB }}.agentguard_cim_event AS
SELECT
  event_time,
  multi_if(
    hook_name = 'session_start',      'session_start',
    hook_name = 'subagent_spawning',  'session_start',
    hook_name = 'session_end',        'session_end',
    hook_name = 'user_prompt_submit', 'user_input',
    hook_name = 'llm_output',         'llm_response',
    hook_name = 'before_tool_call',   'tool_invoke',
    hook_name = 'after_tool_call',    'tool_complete',
    hook_name = 'prompt_context',     'prompt_context',
    hook_name = 'llm_context',        'llm_context',
    'other'
  )                                                                AS event_type,
  agent_type,
  agent_id,
  deployment_id,
  session_id,
  run_id,
  if(provider != '', provider,
     multi_if(
       position(if(model != '', model, json_value(event_data, '$.model')), '@') > 0, 'vertex',
       match(if(model != '', model, json_value(event_data, '$.model')), '^(us\\.|eu\\.|ap\\.)?anthropic\\.'), 'bedrock',
       if(model != '', model, json_value(event_data, '$.model')) != '', 'anthropic',
       ''
     ))                                                            AS provider,
  if(model != '', model, json_value(event_data, '$.model'))       AS model,
  if(tool_name != '', tool_name,
     json_value(event_data, '$.tool_name'))                       AS tool_name,
  json_query(event_data, '$.tool_input')                          AS tool_input,
  json_query(event_data, '$.tool_response')                       AS tool_result,
  json_value(event_data, '$.tool_response.interrupted') != 'true' AS tool_success,
  if(hook_name = 'after_tool_call',
     to_int64(to_float64_or_zero(json_value(event_data, '$.duration_ms'))), 0) AS tool_duration_ms,
  json_value(event_data, '$.prompt')                              AS user_message,
  json_value(event_data, '$.last_assistant_message')              AS assistant_message,
  hook_decision,
  block_reason,
  hook_name                                                       AS raw_hook_name,
  event_data                                                      AS raw_event_data
FROM {{ .DB }}.agentguard_hook_events
WHERE agent_type = 'claudecode'
  AND hook_name IN (
    'session_start', 'subagent_spawning', 'session_end',
    'user_prompt_submit',
    'before_tool_call', 'after_tool_call',
    'llm_output',
    'prompt_context', 'llm_context'
  )
