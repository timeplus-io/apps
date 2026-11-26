-- Hook-per-span agents (the Codex plugin): sub-agent stop, compaction, interrupted turns and
-- permission requests, as agentguard_hook_events rows. `event_data` is the span's attributes plus
-- the keys the other plugins use for the same facts (`agent_id`, `agent_type`, `trigger`).
CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_hook_bridge_openinference_hooks
INTO {{ .DB }}.agentguard_hook_events AS
SELECT
  if (span_attributes['agentguard.hook_name'] = 'subagent_stop',
    'subagent_ended', span_attributes['agentguard.hook_name'])            AS hook_name,
  if (span_attributes['agentguard.hook_name'] IN ('subagent_stop', 'post_compact'),
    to_datetime64(end_time_ns / 1000000000, 3, 'UTC'),
    to_datetime64(start_time_ns / 1000000000, 3, 'UTC'))                  AS event_time,
  span_attributes['session.id']                                           AS session_id,
  if (span_attributes['run.id'] != '',
    span_attributes['run.id'], span_attributes['session.id'])             AS run_id,
  resource_attributes['agent.id']                                         AS agent_id,
  resource_attributes['deployment.id']                                    AS deployment_id,
  resource_attributes['deployment.name']                                  AS deployment_name,
  ''                                                                      AS session_key,
  span_attributes['tool.name']                                            AS tool_name,
  if (map_contains(span_attributes, 'llm.provider'),
    span_attributes['llm.provider'],
    split_by_string('/', span_attributes['llm.model_name'])[1])           AS provider,
  split_by_string('/', span_attributes['llm.model_name'])[-1]             AS model,
  'observe'                                                               AS hook_decision,
  ''                                                                      AS block_reason,
  to_json_string(map_update(span_attributes, map_cast(
    ['agent_id', 'agent_type', 'trigger'],
    [span_attributes['agentguard.subagent.id'], span_attributes['agentguard.subagent.type'],
     span_attributes['codex.compact.trigger']])))                         AS event_data,
  service_name                                                            AS agent_type
FROM {{ .DB }}.otel_traces
WHERE _tp_time > earliest_ts()
  AND span_attributes['agentguard.hook_name'] IN ('subagent_stop', 'pre_compact', 'post_compact', 'interrupt', 'permission_request')
