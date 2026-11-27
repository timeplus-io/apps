-- Replaces mv_cim_metrics_hermes_llm (#72), which selected a constant as `agent_type` and so let its WHERE pass every
-- agent. `agent_type` is selected as the column here: an alias with a column's name replaces the
-- column in WHERE. It reads from now on, so an upgrade does not write the stored rows again.
-- The old view only read `post_api_request` rows, which only Hermes sends, so it did not over-count.
CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_cim_metrics_hermes_llm_v2
INTO {{ .DB }}.agentguard_cim_metrics AS
SELECT
  event_time,
  metric_name,
  metric_value,
  agent_type,
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
WHERE agent_type = 'hermes'
  AND hook_name = 'post_api_request'
