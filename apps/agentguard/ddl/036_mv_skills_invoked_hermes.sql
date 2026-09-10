CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_skills_invoked_hermes
INTO {{ .DB }}.agentguard_skills AS
SELECT
  event_time, agent_id, session_id, deployment_id, agent_type,
  json_value(event_data, '$.args.name') AS skill_name,
  'invoked' AS skill_action,
  if(position(json_value(event_data, '$.args.name'), ':') > 0,
    split_by_string(':', json_value(event_data, '$.args.name'))[1],
    '') AS skill_namespace,
  if(position(json_value(event_data, '$.args.name'), ':') > 0,
    'plugin', 'user') AS skill_source_type,
  json_value(event_data, '$.args.path') AS skill_location,
  ''  AS skill_description,
  json_value(event_data, '$.args.args') AS skill_args
FROM {{ .DB }}.agentguard_hook_events
WHERE _tp_time > earliest_ts()
  AND hook_name = 'pre_tool_call'
  AND tool_name = 'skill_view'
  AND agent_type = 'hermes'
  AND skill_name != ''
