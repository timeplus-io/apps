CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_cim_metrics_openclaw_llm
INTO {{ .DB }}.agentguard_cim_metrics AS
SELECT
  event_time,
  metric_name,
  metric_value,
  'openclaw'                                                              AS agent_type,
  agent_id,
  deployment_id,
  session_id,
  map_cast(
    ['model', 'provider', 'stop_reason', 'run_id'],
    [model, provider, json_value(raw_event_data, '$.lastAssistant.stopReason'), run_id]
  )                                                                       AS tags
FROM (
  SELECT
    e.event_time,
    e.agent_id,
    e.deployment_id,
    e.session_id,
    e.run_id,
    e.model,
    e.provider,
    e.raw_event_data,
    if(r.latency_ms > 0, r.latency_ms, to_float64(0))                    AS latency_ms
  FROM {{ .DB }}.agentguard_cim_event AS e
  LEFT JOIN {{ .DB }}.agentguard_run_latency AS r ON r.run_id = e.run_id
  WHERE e.agent_type = 'openclaw'
    AND e.event_type = 'llm_response'
)
ARRAY JOIN
  ['llm.call', 'llm.input_tokens', 'llm.output_tokens', 'llm.total_tokens',
   'llm.cache_read_tokens', 'llm.cache_write_tokens', 'llm.latency_ms']  AS metric_name,
  [
    to_float64(1),
    to_float64_or_zero(json_extract_string(raw_event_data, 'lastAssistant', 'usage', 'input')),
    to_float64_or_zero(json_extract_string(raw_event_data, 'lastAssistant', 'usage', 'output')),
    to_float64_or_zero(json_extract_string(raw_event_data, 'lastAssistant', 'usage', 'totalTokens')),
    to_float64_or_zero(json_extract_string(raw_event_data, 'lastAssistant', 'usage', 'cacheRead')),
    to_float64_or_zero(json_extract_string(raw_event_data, 'lastAssistant', 'usage', 'cacheWrite')),
    latency_ms
  ]                                                                       AS metric_value
