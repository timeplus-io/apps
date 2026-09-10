CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_cim_openclaw
INTO {{ .DB }}.agentguard_cim_event AS
SELECT
  event_time,
  multi_if(
    hook_name = 'session_start',    'session_start',
    hook_name = 'session_end',      'session_end',
    hook_name = 'message_received', 'user_input',
    hook_name = 'llm_input',        'llm_request',
    hook_name = 'llm_output',       'llm_response',
    hook_name = 'before_tool_call', 'tool_invoke',
    hook_name = 'after_tool_call',  'tool_complete',
    'other'
  )                                                                        AS event_type,
  agent_type,
  agent_id,
  deployment_id,
  session_id,
  run_id,
  if(provider != '', provider,
     json_value(event_data, '$.provider'))                                 AS provider,
  if(model != '', model,
     json_value(event_data, '$.model'))                                    AS model,
  if(tool_name != '', tool_name,
     json_value(event_data, '$.toolName'))                                 AS tool_name,
  json_query(event_data, '$.params')                                       AS tool_input,
  json_query(event_data, '$.result')                                       AS tool_result,
  json_value(event_data, '$.error') = ''                                   AS tool_success,
  json_extract_int(event_data, 'durationMs')                               AS tool_duration_ms,
  if(hook_name = 'llm_input',
     json_value(event_data, '$.prompt'),
     json_value(event_data, '$.content'))                                  AS user_message,
  json_value(event_data, '$.assistantTexts[0]')                            AS assistant_message,
  hook_decision,
  block_reason,
  hook_name                                                                AS raw_hook_name,
  event_data                                                               AS raw_event_data
FROM {{ .DB }}.agentguard_hook_events
WHERE agent_type = 'openclaw'
  AND hook_name IN (
    'session_start', 'session_end',
    'message_received',
    'llm_input', 'llm_output',
    'before_tool_call', 'after_tool_call'
  )
