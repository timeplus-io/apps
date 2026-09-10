CREATE MUTABLE STREAM IF NOT EXISTS {{ .DB }}.agentguard_run_latency
(
  run_id     string,
  latency_ms float64
) PRIMARY KEY (run_id)
