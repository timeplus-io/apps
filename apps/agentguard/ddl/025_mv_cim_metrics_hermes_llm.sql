CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_cim_metrics_hermes_llm
INTO {{ .DB }}.agentguard_cim_metrics AS
SELECT
  event_time,
  metric_name,
  metric_value,
  'hermes'                                                              AS agent_type,
  agent_id,
  deployment_id,
  session_id,
  map_cast(
    ['model', 'provider', 'run_id'],
    [model, provider, run_id]
  )                                                                     AS tags
FROM {{ .DB }}.agentguard_hook_events
ARRAY JOIN
  ['llm.call', 'llm.input_tokens', 'llm.output_tokens', 'llm.total_tokens',
   'llm.cache_read_tokens', 'llm.cache_write_tokens', 'llm.latency_ms']  AS metric_name,
  [
    to_float64(1),
    to_float64_or_zero(json_extract_string(event_data, 'usage', 'input_tokens')),
    to_float64_or_zero(json_extract_string(event_data, 'usage', 'output_tokens')),
    to_float64_or_zero(json_extract_string(event_data, 'usage', 'input_tokens'))
      + to_float64_or_zero(json_extract_string(event_data, 'usage', 'output_tokens')),
    to_float64_or_zero(json_extract_string(event_data, 'usage', 'cache_read_input_tokens')),
    to_float64_or_zero(json_extract_string(event_data, 'usage', 'cache_creation_input_tokens')),
    to_float64_or_zero(json_extract_string(event_data, 'api_duration')) * 1000
  ]                                                                     AS metric_value
WHERE _tp_time > earliest_ts()
  AND agent_type = 'hermes'
  AND hook_name = 'post_api_request'
