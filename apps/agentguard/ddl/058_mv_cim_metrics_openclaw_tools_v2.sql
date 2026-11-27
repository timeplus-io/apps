-- Replaces mv_cim_metrics_openclaw_tools (#72), which selected a constant as `agent_type` and so let its WHERE pass every
-- agent. `agent_type` is selected as the column here: an alias with a column's name replaces the
-- column in WHERE. It reads from now on, so an upgrade does not write the stored rows again.
CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_cim_metrics_openclaw_tools_v2
INTO {{ .DB }}.agentguard_cim_metrics AS
SELECT
  event_time,
  metric_name,
  metric_value,
  agent_type,
  agent_id,
  deployment_id,
  session_id,
  map_cast(['tool_name', 'model', 'provider', 'run_id'], [tool_name, model, provider, run_id]) AS tags
FROM {{ .DB }}.agentguard_cim_event
ARRAY JOIN
  ['tool.call', 'tool.success', 'tool.duration_ms']           AS metric_name,
  [
    to_float64(1),
    if(tool_success, to_float64(1), to_float64(0)),
    to_float64(tool_duration_ms)
  ]                                                            AS metric_value
WHERE agent_type = 'openclaw'
  AND event_type = 'tool_complete'
