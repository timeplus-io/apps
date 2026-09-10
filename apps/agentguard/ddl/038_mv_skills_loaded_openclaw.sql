CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_skills_loaded_openclaw
INTO {{ .DB }}.agentguard_skills AS
SELECT
  event_time, agent_id, session_id, deployment_id, agent_type,
  trim(skill_tuple.1)    AS skill_name,
  'loaded'               AS skill_action,
  if(position(trim(skill_tuple.1), ':') > 0,
     split_by_string(':', trim(skill_tuple.1))[1], '') AS skill_namespace,
  CASE
    WHEN position(skill_tuple.3, '/.openclaw/')        > 0 THEN 'managed'
    WHEN position(skill_tuple.3, '/.config/openclaw/') > 0 THEN 'managed'
    WHEN position(skill_tuple.3, '/.agents/')          > 0 THEN 'personal'
    WHEN position(skill_tuple.3, 'node_modules')       > 0 THEN 'bundled'
    WHEN length(skill_tuple.3)                         > 0 THEN 'workspace'
    ELSE 'unknown'
  END                    AS skill_source_type,
  trim(skill_tuple.3)    AS skill_location,
  trim(skill_tuple.2)    AS skill_description,
  ''                     AS skill_args
FROM {{ .DB }}.agentguard_hook_events
ARRAY JOIN array_zip(
  extract_all(event_data, '<name>([a-zA-Z][a-zA-Z0-9-]*)</name>'),
  array_resize(
    extract_all(event_data, '<description>([^<]+)</description>'),
    length(extract_all(event_data, '<name>([a-zA-Z][a-zA-Z0-9-]*)</name>')),
    ''
  ),
  array_resize(
    extract_all(event_data, '<location>([^<]+)</location>'),
    length(extract_all(event_data, '<name>([a-zA-Z][a-zA-Z0-9-]*)</name>')),
    ''
  )
) AS skill_tuple
WHERE _tp_time > earliest_ts()
  AND hook_name = 'llm_input'
  AND agent_type = 'openclaw'
  AND length(trim(skill_tuple.1)) > 0
