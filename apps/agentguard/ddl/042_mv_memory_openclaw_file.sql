CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_memory_openclaw_file
INTO {{ .DB }}.agentguard_memory_ops AS
SELECT
  event_time,
  session_id,
  agent_id,
  agent_type,
  deployment_id,
  'openclaw_file' AS memory_source,
  CASE
    WHEN tool_name = 'write' THEN 'save'
    WHEN tool_name = 'read'  THEN 'read'
    ELSE 'other'
  END AS memory_op,
  tool_name,
  '' AS server_name,
  json_value(event_data, '$.params.path') AS memory_path,
  json_query(event_data, '$.params') AS content_payload
FROM {{ .DB }}.agentguard_hook_events
WHERE _tp_time > earliest_ts()
  AND hook_name = 'before_tool_call'
  AND agent_type = 'openclaw'
  AND tool_name IN ('write', 'read')
  AND match(json_value(event_data, '$.params.path'), '\.openclaw/workspace/memory/')
