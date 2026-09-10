CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_memory_claudecode_automem
INTO {{ .DB }}.agentguard_memory_ops AS
SELECT
  event_time,
  session_id,
  agent_id,
  agent_type,
  deployment_id,
  'auto_memory' AS memory_source,
  CASE
    WHEN tool_name = 'Write' THEN 'save'
    WHEN tool_name = 'Edit'  THEN 'update'
    WHEN tool_name = 'Read'  THEN 'read'
    ELSE 'other'
  END AS memory_op,
  tool_name,
  '' AS server_name,
  json_value(event_data, '$.tool_input.file_path') AS memory_path,
  json_query(event_data, '$.tool_input') AS content_payload
FROM {{ .DB }}.agentguard_hook_events
WHERE _tp_time > earliest_ts()
  AND hook_name = 'before_tool_call'
  AND agent_type = 'claudecode'
  AND tool_name IN ('Write', 'Edit', 'Read')
  AND position(json_value(event_data, '$.tool_input.file_path'), '/.claude/projects/') > 0
  AND position(json_value(event_data, '$.tool_input.file_path'), '/memory/') > 0
