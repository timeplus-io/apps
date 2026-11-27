-- Claude Code on the hook path: one llm.call per model request. The plugin (0.7.0 or later) reads
-- the requests of a turn from the transcript on Stop, and those of a sub-agent on SubagentStop, and
-- sends each as an `llm_call` row with the usage, the model and the request time
-- (timeplus-io/AgentGuard#324). `event_time` is the time of the response.
-- Token counts have the meaning of the Anthropic API: input tokens do not include cached tokens.
-- llm.latency_ms is left out when the row has no duration (older Claude Code versions).
-- mv_cim_metrics_claudecode_otel writes the same metrics from Claude Code's own telemetry, so a
-- session that reports on both paths is counted twice: use one of them.
CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_cim_metrics_claudecode_llm
INTO {{ .DB }}.agentguard_cim_metrics AS
SELECT
  event_time,
  metric_name,
  metric_value,
  agent_type,
  agent_id,
  deployment_id,
  session_id,
  map_cast(['model', 'provider', 'run_id', 'sidechain'],
    [model, provider, run_id, json_value(event_data, '$.is_sidechain')])    AS tags
FROM {{ .DB }}.agentguard_hook_events
ARRAY JOIN
  ['llm.call', 'llm.input_tokens', 'llm.output_tokens', 'llm.total_tokens',
   'llm.cache_read_tokens', 'llm.cache_write_tokens', 'llm.latency_ms']     AS metric_name,
  [
    to_float64(1),
    to_float64_or_zero(json_value(event_data, '$.usage.input_tokens')),
    to_float64_or_zero(json_value(event_data, '$.usage.output_tokens')),
    to_float64_or_zero(json_value(event_data, '$.usage.total_tokens')),
    to_float64_or_zero(json_value(event_data, '$.usage.cache_read_input_tokens')),
    to_float64_or_zero(json_value(event_data, '$.usage.cache_creation_input_tokens')),
    to_float64_or_zero(json_value(event_data, '$.duration_ms'))
  ]                                                                         AS metric_value
WHERE _tp_time > earliest_ts()
  AND agent_type = 'claudecode'
  AND hook_name = 'llm_call'
  AND (metric_name != 'llm.latency_ms' OR json_value(event_data, '$.duration_ms') != '')
