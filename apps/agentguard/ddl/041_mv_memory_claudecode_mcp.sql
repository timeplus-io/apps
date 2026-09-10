CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_memory_claudecode_mcp
INTO {{ .DB }}.agentguard_memory_ops AS
SELECT
  event_time,
  session_id,
  agent_id,
  agent_type,
  deployment_id,
  'mcp' AS memory_source,
  CASE
    WHEN match(lower(tool_name), 'save|store|remember|upsert|embed|write') THEN 'save'
    WHEN match(lower(tool_name), 'search|query|recall|retrieve|find')      THEN 'search'
    WHEN match(lower(tool_name), 'read|load|get|fetch|observation')        THEN 'read'
    WHEN match(lower(tool_name), 'delete|forget|remove')                   THEN 'delete'
    WHEN match(lower(tool_name), 'update|edit|patch')                      THEN 'update'
    ELSE 'other'
  END AS memory_op,
  tool_name,
  split_by_string('__', tool_name)[2] AS server_name,
  '' AS memory_path,
  json_query(event_data, '$.tool_input') AS content_payload
FROM {{ .DB }}.agentguard_hook_events
WHERE _tp_time > earliest_ts()
  AND hook_name = 'before_tool_call'
  AND agent_type = 'claudecode'
  AND match(tool_name, '^mcp__')
  AND match(lower(tool_name), 'memory|mem|recall|remember|store|knowledge|forget|embedding')
