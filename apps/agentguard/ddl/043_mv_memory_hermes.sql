CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_memory_hermes
INTO {{ .DB }}.agentguard_memory_ops AS
SELECT
  event_time,
  session_id,
  agent_id,
  agent_type,
  deployment_id,
  'hermes_memory' AS memory_source,
  CASE
    WHEN json_value(event_data, '$.args.action') = 'add' THEN 'save'
    WHEN json_value(event_data, '$.args.action') = 'replace' THEN 'update'
    WHEN json_value(event_data, '$.args.action') = 'remove' THEN 'delete'
    ELSE 'other'
  END AS memory_op,
  tool_name,
  '' AS server_name,
  json_value(event_data, '$.args.target') AS memory_path,
  json_query(event_data, '$.args') AS content_payload
FROM {{ .DB }}.agentguard_hook_events
WHERE _tp_time > earliest_ts()
  AND hook_name = 'pre_tool_call'
  AND agent_type = 'hermes'
  AND tool_name = 'memory'
