-- mv_skills_invoked_codex for the hook-event path: a `pre_tool_use` row whose command reads
-- `<skill>/SKILL.md` counts as invoking that skill. `event_time` is the row's, the same instant as
-- its `tool_invoke` row from mv_cim_codex_v2, which is how Agent Rooms matches the two.
CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_skills_invoked_codex_hooks
INTO {{ .DB }}.agentguard_skills AS
SELECT
  event_time,
  agent_id,
  session_id,
  deployment_id,
  agent_type,
  extract(json_value(event_data, '$.tool_input.command'),
    '([A-Za-z0-9._-]+)/SKILL\\.md')                                 AS skill_name,
  'invoked'                                                         AS skill_action,
  ''                                                                AS skill_namespace,
  multi_if(
    position(json_value(event_data, '$.tool_input.command'), '/skills/.system/') > 0, 'system',
    position(json_value(event_data, '$.tool_input.command'), '/.codex/') > 0, 'user',
    'project')                                                      AS skill_source_type,
  extract(json_value(event_data, '$.tool_input.command'),
    '([^\\s\'"]+/SKILL\\.md)')                                      AS skill_location,
  ''                                                                AS skill_description,
  ''                                                                AS skill_args
FROM {{ .DB }}.agentguard_hook_events
WHERE _tp_time > earliest_ts()
  AND agent_type = 'codex'
  AND hook_name = 'pre_tool_use'
  AND json_extract_string(event_data, 'agentguard.export') = 'hooks'
  AND match(json_value(event_data, '$.tool_input.command'),
    '(^|[\\s;&|(])(cat|bat|head|tail|less|more|nl|sed|awk)\\s[^;&|]*[A-Za-z0-9._-]+/SKILL\\.md')
