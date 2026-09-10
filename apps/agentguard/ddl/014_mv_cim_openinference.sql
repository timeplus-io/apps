CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_cim_openinference
INTO {{ .DB }}.agentguard_cim_event AS
SELECT
  multi_if(
    idx = 1,
    to_datetime64(start_time_ns / 1000000000, 3, 'UTC'),
    to_datetime64(end_time_ns / 1000000000, 3, 'UTC')
  )                                                                 AS event_time,
  multi_if(
    idx = 1,
    multi_if(
      span_attributes['openinference.span.kind'] == 'LLM', 'llm_request',
      span_attributes['openinference.span.kind'] == 'TOOL', 'tool_invoke',
      span_attributes['agentguard.span.kind'] == 'SESSION', 'session_start',
      'other'
    ),
    multi_if(
	  span_attributes['openinference.span.kind'] == 'LLM', 'llm_response',
      span_attributes['openinference.span.kind'] == 'TOOL', 'tool_complete',
      span_attributes['agentguard.span.kind'] == 'SESSION', 'session_end',
      'other'
    )
  )                                                                 AS event_type,
  service_name                                                      AS agent_type,
  resource_attributes['agent.id']                                   AS agent_id,
  resource_attributes['deployment.id']                              AS deployment_id,
  span_attributes['session.id']                                     AS session_id,
  ''                                                                AS run_id,
  if (map_contains(span_attributes, 'llm.provider'),
    span_attributes['llm.provider'],
    split_by_string('/', span_attributes['llm.model_name'])[1])     AS provider,
  split_by_string('/', span_attributes['llm.model_name'])[-1]       AS model,
  span_attributes['tool.name']                                      AS tool_name,
  span_attributes['tool.parameters']                                AS tool_input,
  if (span_attributes['openinference.span.kind'] == 'TOOL',
    span_attributes['output.value'], '')                            AS tool_result,
  true                                                              AS tool_success,
  if(idx = 2, int_div(end_time_ns - start_time_ns, 1000000), 0)     AS tool_duration_ms,
  json_value(array_filter(
      m -> json_value(m, '$.role') = 'user',
      json_extract_array(span_attributes['input.value'], 'messages')
    )[-1], '$.content')                                             AS user_message,
  span_attributes['llm.output_messages.0.message.content']          AS assistant_message,
  ''                                                                AS hook_decision,
  ''                                                                AS block_reason,
  span_name                                                         AS raw_hook_name,
  to_json_string(span_attributes)                                   AS raw_event_data
FROM {{ .DB }}.otel_traces
ARRAY JOIN array_cast(1, 2) AS idx
WHERE _tp_time > earliest_ts()
  AND event_type != 'other'
