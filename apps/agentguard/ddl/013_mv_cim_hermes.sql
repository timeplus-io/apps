CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_cim_hermes
INTO {{ .DB }}.agentguard_cim_event AS
SELECT
  event_time,
  multi_if(
    hook_name = 'on_session_start',    'session_start',
    hook_name = 'on_session_end',      'session_end',
    hook_name = 'on_session_finalize', 'session_end',
    hook_name = 'on_session_reset',    'session_start',
    hook_name = 'pre_llm_call',        'user_input',
    hook_name = 'post_llm_call',       'llm_response',
    hook_name = 'pre_api_request',     'llm_request',
    hook_name = 'pre_tool_call',       'tool_invoke',
    hook_name = 'post_tool_call',      'tool_complete',
    'other'
  )                                                                    AS event_type,
  agent_type,
  agent_id,
  deployment_id,
  session_id,
  run_id,
  if(provider != '', provider,
     json_value(event_data, '$.provider'))                             AS provider,
  model,
  if(tool_name != '', tool_name,
     json_value(event_data, '$.tool_name'))                            AS tool_name,
  json_query(event_data, '$.args')                                     AS tool_input,
  json_query(event_data, '$.result')                                   AS tool_result,
  true                                                                 AS tool_success,
  0                                                                    AS tool_duration_ms,
  json_value(event_data, '$.user_message')                             AS user_message,
  json_value(event_data, '$.assistant_response')                       AS assistant_message,
  hook_decision,
  block_reason,
  hook_name                                                            AS raw_hook_name,
  event_data                                                           AS raw_event_data
FROM {{ .DB }}.agentguard_hook_events
WHERE _tp_time > earliest_ts()
  AND agent_type = 'hermes'
  AND hook_name IN (
    'on_session_start', 'on_session_end', 'on_session_finalize', 'on_session_reset',
    'pre_llm_call', 'post_llm_call',
    'pre_api_request',
    'pre_tool_call', 'post_tool_call'
  )
