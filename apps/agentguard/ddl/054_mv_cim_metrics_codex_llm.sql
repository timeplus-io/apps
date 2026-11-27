-- Codex on the hook-event path: one llm.call per model request attempt (`post_model_request`), with
-- the token counts of the hook's `token_usage`. Same metrics as mv_cim_metrics_openinference_llm
-- gives the same session on the OTel path, plus llm.cache_write_tokens when Codex reports it.
-- Codex counts cached tokens inside its input tokens. llm.latency_ms needs the plugin to have seen
-- the request start, so it is left out when the row has no duration.
CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_cim_metrics_codex_llm
INTO {{ .DB }}.agentguard_cim_metrics AS
SELECT
  event_time,
  metric_name,
  metric_value,
  agent_type,
  agent_id,
  deployment_id,
  session_id,
  map_cast(['model', 'provider', 'run_id'],
    [split_by_string('/', model)[-1], provider, run_id])                     AS tags
FROM {{ .DB }}.agentguard_hook_events
ARRAY JOIN
  ['llm.call', 'llm.total_tokens', 'llm.input_tokens', 'llm.output_tokens', 'llm.cache_read_tokens', 'llm.cache_write_tokens', 'llm.latency_ms'] AS metric_name,
  [
    to_float64(1),
    to_float64_or_zero(json_value(event_data, '$.token_usage.total_tokens')),
    to_float64_or_zero(json_value(event_data, '$.token_usage.input_tokens')),
    to_float64_or_zero(json_value(event_data, '$.token_usage.output_tokens')),
    to_float64_or_zero(json_value(event_data, '$.token_usage.cached_input_tokens')),
    to_float64_or_zero(json_value(event_data, '$.token_usage.cache_write_input_tokens')),
    to_float64(json_extract_int(event_data, 'agentguard.duration_ms'))
  ]                                                                          AS metric_value
WHERE _tp_time > earliest_ts()
  AND agent_type = 'codex'
  AND hook_name = 'post_model_request'
  AND json_extract_string(event_data, 'agentguard.export') = 'hooks'
  AND (metric_name != 'llm.latency_ms' OR json_has(event_data, 'agentguard.duration_ms'))
  AND (metric_name != 'llm.cache_write_tokens' OR json_value(event_data, '$.token_usage.cache_write_input_tokens') != '')
