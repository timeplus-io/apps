CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_skills_loaded_claudecode
INTO {{ .DB }}.agentguard_skills AS
SELECT
  event_time, agent_id, session_id, deployment_id, agent_type,
  trim(sn) AS skill_name,
  'loaded'  AS skill_action,
  if(position(trim(sn), ':') > 0,
     split_by_string(':', trim(sn))[1], '') AS skill_namespace,
  if(position(trim(sn), ':') > 0, 'plugin', 'user') AS skill_source_type,
  '' AS skill_location,
  '' AS skill_description,
  '' AS skill_args
FROM {{ .DB }}.agentguard_hook_events
ARRAY JOIN extract_all(event_data, '---..name: ([a-zA-Z][a-zA-Z0-9:-]*)') AS sn
WHERE _tp_time > earliest_ts()
  AND hook_name = 'prompt_context'
  AND agent_type = 'claudecode'
  AND length(trim(sn)) > 0
