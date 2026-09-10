CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_run_latency
INTO {{ .DB }}.agentguard_run_latency AS
SELECT
  run_id,
  to_float64_or_zero(json_extract_string(event_data, 'durationMs')) AS latency_ms
FROM {{ .DB }}.agentguard_hook_events
WHERE hook_name = 'agent_end'
