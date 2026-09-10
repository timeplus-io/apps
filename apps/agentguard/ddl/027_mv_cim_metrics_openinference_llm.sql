CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_cim_metrics_openinference_llm
INTO {{ .DB }}.agentguard_cim_metrics AS
SELECT
  to_datetime64(end_time_ns / 1000000000, 3, 'UTC')                          AS event_time,
  metric_name,
  metric_value,
  service_name                                                               AS agent_type,
  resource_attributes['agent.id']                                            AS agent_id,
  resource_attributes['deployment.id']                                       AS deployment_id,
  span_attributes['session.id']                                              AS session_id,
  map_cast(
    ['model', 'provider', 'trace_id'],
    [
      split_by_string('/', span_attributes['llm.model_name'])[-1],
      if (map_contains(span_attributes, 'llm.provider'),
        span_attributes['llm.provider'],
        split_by_string('/', span_attributes['llm.model_name'])[1]),
      trace_id
    ]
  )                                                                          AS tags
FROM {{ .DB }}.otel_traces
ARRAY JOIN
  ['llm.call', 'llm.total_tokens', 'llm.input_tokens', 'llm.output_tokens', 'llm.cache_read_tokens', 'llm.latency_ms'] AS metric_name,
  [
    to_float64(1),
    to_float64_or_zero(span_attributes['llm.token_count.total']),
    to_float64_or_zero(span_attributes['llm.token_count.prompt']),
    to_float64_or_zero(span_attributes['llm.token_count.completion']),
    to_float64_or_zero(span_attributes['llm.token_count.prompt_details.cache_read']),
    (end_time_ns - start_time_ns) / 1000000
  ]                                                                          AS metric_value
WHERE _tp_time > earliest_ts()
  AND span_attributes['openinference.span.kind'] = 'LLM'
