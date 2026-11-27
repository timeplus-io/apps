-- Codex sessions sent on the plugin's hook-event path (AGENTGUARD_CODEX_EXPORT=hooks, plugin 0.3.0
-- or later): one agentguard_hook_events row per Codex hook, `event_data` is the hook payload.
-- Only rows marked `"agentguard.export": "hooks"` are read. On the OTel path the bridge views write
-- rows into the same stream with the same agent_type, and those sessions already have their CIM
-- rows from mv_cim_openinference and mv_cim_openinference_hooks.
-- A model request gives an llm_request row at its start and an llm_response row at its end, as its
-- span does on the OTel path. A prompt or reply inside a sub-agent is left out: it is not part of
-- the conversation with the user.
--
-- Replaces mv_cim_codex (#75, #76). It reads from now on, so an upgrade does not write the stored
-- rows again. What is new:
-- - `tool_success` is false when an MCP tool response has `isError: true`. A shell call still counts
--   as a success whatever its exit status: the hook gives its output as text, without the status.
-- - `permission_request` becomes a row of that event type, with the tool name and input.
CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_cim_codex_v2
INTO {{ .DB }}.agentguard_cim_event AS
SELECT
  if (cim_type = 'llm_request',
    add_milliseconds(h.event_time, -json_extract_int(h.event_data, 'agentguard.duration_ms')),
    h.event_time)                                                   AS event_time,
  cim_type                                                          AS event_type,
  h.agent_type                                                      AS agent_type,
  h.agent_id                                                        AS agent_id,
  h.deployment_id                                                   AS deployment_id,
  h.session_id                                                      AS session_id,
  h.run_id                                                          AS run_id,
  h.provider                                                        AS provider,
  split_by_string('/', h.model)[-1]                                 AS model,
  if (h.hook_name IN ('pre_tool_use', 'post_tool_use', 'permission_request'), h.tool_name, '') AS tool_name,
  multi_if(
    h.hook_name NOT IN ('pre_tool_use', 'post_tool_use', 'permission_request'), '',
    json_type(h.event_data, 'tool_input') = 'String', json_extract_string(h.event_data, 'tool_input'),
    json_type(h.event_data, 'tool_input') IN ('Object', 'Array'), json_extract_raw(h.event_data, 'tool_input'),
    '')                                                             AS tool_input,
  multi_if(
    h.hook_name != 'post_tool_use', '',
    json_type(h.event_data, 'tool_response') = 'String', json_extract_string(h.event_data, 'tool_response'),
    json_type(h.event_data, 'tool_response') = 'Null', '',
    json_extract_raw(h.event_data, 'tool_response'))                AS tool_result,
  NOT (h.hook_name = 'post_tool_use'
    AND json_value(h.event_data, '$.tool_response.isError') = 'true')  AS tool_success,
  if (h.hook_name = 'post_tool_use',
    json_extract_int(h.event_data, 'agentguard.duration_ms'), 0)    AS tool_duration_ms,
  if (h.hook_name = 'user_prompt_submit',
    json_value(h.event_data, '$.prompt'), '')                       AS user_message,
  if (h.hook_name = 'stop',
    json_value(h.event_data, '$.last_assistant_message'), '')       AS assistant_message,
  h.hook_decision                                                   AS hook_decision,
  h.block_reason                                                    AS block_reason,
  h.hook_name                                                       AS raw_hook_name,
  h.event_data                                                      AS raw_event_data
FROM {{ .DB }}.agentguard_hook_events AS h
ARRAY JOIN multi_if(
    h.hook_name IN ('session_start', 'subagent_start'), ['session_start'],
    h.hook_name = 'session_end', ['session_end'],
    h.hook_name = 'user_prompt_submit', ['user_input'],
    h.hook_name = 'stop', ['llm_response'],
    h.hook_name = 'pre_tool_use', ['tool_invoke'],
    h.hook_name = 'post_tool_use', ['tool_complete'],
    h.hook_name = 'permission_request', ['permission_request'],
    ['llm_request', 'llm_response'])                                AS cim_type
WHERE h.agent_type = 'codex'
  AND json_extract_string(h.event_data, 'agentguard.export') = 'hooks'
  AND (h.hook_name IN ('session_start', 'subagent_start', 'session_end', 'pre_tool_use', 'post_tool_use', 'post_model_request', 'permission_request')
    OR (h.hook_name IN ('user_prompt_submit', 'stop')
      AND json_value(h.event_data, '$.agent_id') = ''))
