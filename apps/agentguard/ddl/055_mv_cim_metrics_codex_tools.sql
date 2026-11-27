-- tool.call and tool.success for Codex, from its tool_complete rows. It reads agentguard_cim_event,
-- so it counts a Codex tool call on either export path: once per `post_tool_use` hook row, or once
-- per `tool` span.
-- `agent_type` is selected as the column, not as a constant with that alias: an alias with a
-- column's name replaces the column in WHERE, and the filter below would then pass every agent.
CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_cim_metrics_codex_tools
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
  ['tool.call', 'tool.success']                                        AS metric_name,
  [
    to_float64(1),
    if(tool_success, to_float64(1), to_float64(0))
  ]                                                                     AS metric_value
WHERE _tp_time > earliest_ts()
  AND agent_type = 'codex'
  AND event_type = 'tool_complete'
