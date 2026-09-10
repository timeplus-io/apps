CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_skills_invoked_openclaw
INTO {{ .DB }}.agentguard_skills AS
SELECT
  event_time, agent_id, session_id, deployment_id, agent_type,
  extract(json_value(event_data, '$.params.path'),
          '/skills/([a-zA-Z][a-zA-Z0-9-]*)/SKILL') AS skill_name,
  'invoked' AS skill_action,
  ''         AS skill_namespace,
  CASE
    WHEN position(json_value(event_data, '$.params.path'), '/.openclaw/')        > 0 THEN 'managed'
    WHEN position(json_value(event_data, '$.params.path'), '/.config/openclaw/') > 0 THEN 'managed'
    WHEN position(json_value(event_data, '$.params.path'), '/.agents/')          > 0 THEN 'personal'
    WHEN position(json_value(event_data, '$.params.path'), 'node_modules')       > 0 THEN 'bundled'
    WHEN length(json_value(event_data, '$.params.path'))                         > 0 THEN 'workspace'
    ELSE 'unknown'
  END        AS skill_source_type,
  json_value(event_data, '$.params.path') AS skill_location,
  ''         AS skill_description,
  ''         AS skill_args
FROM {{ .DB }}.agentguard_hook_events
WHERE _tp_time > earliest_ts()
  AND hook_name = 'before_tool_call'
  AND tool_name = 'read'
  AND agent_type = 'openclaw'
  AND position(event_data, 'SKILL.md') > 0
  AND extract(json_value(event_data, '$.params.path'),
              '/skills/([a-zA-Z][a-zA-Z0-9-]*)/SKILL') != ''
