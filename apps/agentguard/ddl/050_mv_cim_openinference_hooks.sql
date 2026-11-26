-- Prompt, reply and live session start for agents whose plugin sends one span per hook, named by
-- `agentguard.hook_name` (the Codex plugin). mv_cim_openinference covers the LLM, TOOL and SESSION
-- kind spans; these spans carry no kind, so that a prompt or a reply is never counted as an LLM call.
-- A prompt or reply inside a sub-agent is left out: it is not part of the conversation with the user.
CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_cim_openinference_hooks
INTO {{ .DB }}.agentguard_cim_event AS
SELECT
  to_datetime64(start_time_ns / 1000000000, 3, 'UTC')               AS event_time,
  multi_if(
    span_attributes['agentguard.hook_name'] = 'user_prompt_submit', 'user_input',
    span_attributes['agentguard.hook_name'] = 'stop', 'llm_response',
    'session_start'
  )                                                                 AS event_type,
  service_name                                                      AS agent_type,
  resource_attributes['agent.id']                                   AS agent_id,
  resource_attributes['deployment.id']                              AS deployment_id,
  span_attributes['session.id']                                     AS session_id,
  span_attributes['run.id']                                         AS run_id,
  if (map_contains(span_attributes, 'llm.provider'),
    span_attributes['llm.provider'],
    split_by_string('/', span_attributes['llm.model_name'])[1])     AS provider,
  split_by_string('/', span_attributes['llm.model_name'])[-1]       AS model,
  ''                                                                AS tool_name,
  ''                                                                AS tool_input,
  ''                                                                AS tool_result,
  true                                                              AS tool_success,
  0                                                                 AS tool_duration_ms,
  if (span_attributes['agentguard.hook_name'] = 'user_prompt_submit',
    json_value(array_filter(
        m -> json_value(m, '$.role') = 'user',
        json_extract_array(span_attributes['input.value'], 'messages')
      )[-1], '$.content'), '')                                      AS user_message,
  if (span_attributes['agentguard.hook_name'] = 'stop',
    span_attributes['output.value'], '')                            AS assistant_message,
  ''                                                                AS hook_decision,
  ''                                                                AS block_reason,
  span_name                                                         AS raw_hook_name,
  to_json_string(span_attributes)                                   AS raw_event_data
FROM {{ .DB }}.otel_traces
WHERE _tp_time > earliest_ts()
  AND (span_attributes['agentguard.hook_name'] IN ('session_start', 'subagent_start')
    OR (span_attributes['agentguard.hook_name'] IN ('user_prompt_submit', 'stop')
      AND NOT map_contains(span_attributes, 'agentguard.subagent.id')))
