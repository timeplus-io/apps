CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_cim_metrics_claudecode_tools
INTO {{ .DB }}.agentguard_cim_metrics AS
SELECT
  event_time,
  metric_name,
  metric_value,
  'claudecode' AS agent_type,
  agent_id,
  deployment_id,
  session_id,
  map_cast(['tool_name', 'model', 'provider', 'run_id'], [tool_name, model, provider, run_id]) AS tags
FROM {{ .DB }}.agentguard_cim_event
ARRAY JOIN
  ['tool.call', 'tool.success']             AS metric_name,
  [
    to_float64(1),
    if(tool_success, to_float64(1), to_float64(0))
  ]                                         AS metric_value
WHERE agent_type = 'claudecode'
  AND event_type = 'tool_complete'
