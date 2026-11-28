-- Detection rules: Guard tampering (timeplus-io/apps#86).
-- Attempts to switch off the agent's own guard rails, in shell commands.
-- One row is written per rule that matches, under the rule's own id and severity. A regex in a SQL
-- string needs every backslash doubled: a single \b is a backspace character, and the pattern never matches.
-- Command rules read the command of a shell tool call, not the text of a file being written or read.
CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_rule_tamper
INTO {{ .DB }}.agentguard_security_events AS
SELECT
  event_time     AS detected_at,
  rule_id,
  rule_name,
  severity,
  agent_id,
  deployment_id,
  session_id,
  run_id,
  raw_hook_name  AS hook_name,
  tool_name,
  concat(rule_name, ': ', evidence) AS message,
  raw_event_data AS event_data
FROM {{ .DB }}.agentguard_cim_event
ARRAY JOIN
  ['guard.tamper'] AS rule_id,
  ['Agent guard rails changed or skipped'] AS rule_name,
  ['high'] AS severity,
  [
    -- guard.tamper
    (lower(tool_name) IN ('bash', 'shell', 'exec', 'run_terminal_cmd', 'local_shell', 'terminal', 'computer') AND match(multi_if(json_value(tool_input, '$[0].command') != '', json_value(tool_input, '$[0].command'), json_value(tool_input, '$.command') != '', json_value(tool_input, '$.command'), tool_input), '(sed\\s+-i|>|\\brm\\b|\\bmv\\b|\\btee\\b)[^;&|]*(\\.claude/settings(\\.local)?\\.json|\\.codex/(hooks\\.json|config\\.toml))|\\bunset\\s+AGENTGUARD_|--dangerously-skip-permissions|\\bgit\\s+(commit|push)\\b[^;&|]*--no-verify'))
  ] AS hit,
  [
    -- guard.tamper
    substring(replace_regex(extract(multi_if(json_value(tool_input, '$[0].command') != '', json_value(tool_input, '$[0].command'), json_value(tool_input, '$.command') != '', json_value(tool_input, '$.command'), tool_input), '([^;&|]{0,70}(\\.claude/settings(\\.local)?\\.json|\\.codex/(hooks\\.json|config\\.toml)|unset\\s+AGENTGUARD_\\w*|--dangerously-skip-permissions|--no-verify)[^;&|]{0,40})'), '\\s+', ' '), 1, 160)
  ] AS evidence
WHERE event_type IN ('tool_invoke')
  AND session_id != ''
  AND hit
