CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_hook_bridge_openinference
INTO {{ .DB }}.agentguard_hook_events AS
SELECT
  multi_if(
    idx = 1,
    multi_if(
      span_attributes['openinference.span.kind'] = 'LLM', 'llm_input',
      span_attributes['openinference.span.kind'] = 'TOOL', 'before_tool_call',
      span_attributes['agentguard.span.kind'] = 'SESSION', 'session_start',
      'span_start'
    ),
    multi_if(
      span_attributes['openinference.span.kind'] = 'LLM', 'llm_output',
      span_attributes['openinference.span.kind'] = 'TOOL', 'after_tool_call',
      span_attributes['agentguard.span.kind'] = 'SESSION', 'session_end',
      'span_end'
    )
  )                                                                       AS hook_name,
  multi_if(
    idx = 1,
    to_datetime64(start_time_ns / 1000000000, 3, 'UTC'),
    to_datetime64(end_time_ns / 1000000000, 3, 'UTC')
  )                                                                       AS event_time,
  coalesce(span_attributes['session.id'], trace_id)                       AS session_id,
  coalesce(span_attributes['session.id'], trace_id)                       AS run_id,
  resource_attributes['agent.id']                                         AS agent_id,
  resource_attributes['deployment.id']                                    AS deployment_id,
  resource_attributes['deployment.name']                                  AS deployment_name,
  ''                                                                      AS session_key,
  span_attributes['tool.name']                                            AS tool_name,
  if (map_contains(span_attributes, 'llm.provider'),
    span_attributes['llm.provider'],
    split_by_string('/', span_attributes['llm.model_name'])[1])           AS provider,
  split_by_string('/', span_attributes['llm.model_name'])[-1]             AS model,
  'observe'                                                               AS hook_decision,
  ''                                                                      AS block_reason,
  to_json_string(span_attributes)                                         AS event_data,
  service_name                                                            AS agent_type
FROM {{ .DB }}.otel_traces
ARRAY JOIN array_cast(1, 2) AS idx
WHERE _tp_time > earliest_ts()
  AND (span_attributes['openinference.span.kind'] = 'LLM'
    OR span_attributes['openinference.span.kind'] = 'TOOL'
    OR span_attributes['agentguard.span.kind'] = 'SESSION')
