-- Codex has no skill tool: it uses a skill by reading its SKILL.md through the shell. A tool call
-- whose command reads `<skill>/SKILL.md` counts as invoking that skill. `event_time` is the start
-- of the call, the same instant as its `tool_invoke` row, which is how Agent Rooms matches the two.
CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_skills_invoked_codex
INTO {{ .DB }}.agentguard_skills AS
SELECT
  to_datetime64(start_time_ns / 1000000000, 3, 'UTC')               AS event_time,
  resource_attributes['agent.id']                                   AS agent_id,
  span_attributes['session.id']                                     AS session_id,
  resource_attributes['deployment.id']                              AS deployment_id,
  service_name                                                      AS agent_type,
  extract(json_value(span_attributes['tool.parameters'], '$.command'),
    '([A-Za-z0-9._-]+)/SKILL\\.md')                                 AS skill_name,
  'invoked'                                                         AS skill_action,
  ''                                                                AS skill_namespace,
  multi_if(
    position(json_value(span_attributes['tool.parameters'], '$.command'), '/skills/.system/') > 0, 'system',
    position(json_value(span_attributes['tool.parameters'], '$.command'), '/.codex/') > 0, 'user',
    'project')                                                      AS skill_source_type,
  extract(json_value(span_attributes['tool.parameters'], '$.command'),
    '([^\\s\'"]+/SKILL\\.md)')                                      AS skill_location,
  ''                                                                AS skill_description,
  ''                                                                AS skill_args
FROM {{ .DB }}.otel_traces
WHERE _tp_time > earliest_ts()
  AND service_name = 'codex'
  AND span_attributes['openinference.span.kind'] = 'TOOL'
  AND match(json_value(span_attributes['tool.parameters'], '$.command'),
    '(^|[\\s;&|(])(cat|bat|head|tail|less|more|nl|sed|awk)\\s[^;&|]*[A-Za-z0-9._-]+/SKILL\\.md')
