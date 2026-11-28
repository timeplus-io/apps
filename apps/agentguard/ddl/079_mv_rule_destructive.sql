-- Detection rules: Destructive actions (timeplus-io/apps#86).
-- Destructive actions, in shell commands.
-- One row is written per rule that matches, under the rule's own id and severity. A regex in a SQL
-- string needs every backslash doubled: a single \b is a backspace character, and the pattern never matches.
-- Command rules read the command of a shell tool call, not the text of a file being written or read.
CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_rule_destructive
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
  ['destroy.delete', 'destroy.action'] AS rule_id,
  ['Recursive delete outside the project', 'Destructive action'] AS rule_name,
  ['high', 'medium'] AS severity,
  [
    -- destroy.delete
    (lower(tool_name) IN ('bash', 'shell', 'exec', 'run_terminal_cmd', 'local_shell', 'terminal', 'computer') AND match(multi_if(json_value(tool_input, '$[0].command') != '', json_value(tool_input, '$[0].command'), json_value(tool_input, '$.command') != '', json_value(tool_input, '$.command'), tool_input), '(^|[;&|(]\\s*|\\b(then|do|else)\\s+)(sudo\\s+(-\\S+\\s+)*)?rm\\s+(-[A-Za-z]+\\s+)*-[A-Za-z]*[rR][A-Za-z]*\\s+(-\\S+\\s+)*[\\"\']?(/(\\s|$|\\*|[\\"\'])|~|\\$HOME|\\$\\{HOME\\}|/(etc|usr|var|bin|sbin|home|Users|opt|System)\\b)')),
    -- destroy.action
    (lower(tool_name) IN ('bash', 'shell', 'exec', 'run_terminal_cmd', 'local_shell', 'terminal', 'computer') AND match(multi_if(json_value(tool_input, '$[0].command') != '', json_value(tool_input, '$[0].command'), json_value(tool_input, '$.command') != '', json_value(tool_input, '$.command'), tool_input), '(?i)\\bgit\\s+push\\b[^;&|]*(--force|\\s-f)(\\s|$)[^;&|]*\\b(main|master|trunk|production|prod|release[\\w./\\-]*)\\b|\\bgit\\s+push\\b[^;&|]*\\b(main|master|trunk|production|prod|release[\\w./\\-]*)\\b[^;&|]*(--force|\\s-f)(\\s|$)|\\bgit\\s+reset\\s+--hard\\s+\\S*[~^][0-9]|\\bDROP\\s+(DATABASE|SCHEMA)\\b|\\bkubectl\\s+delete\\s+(ns|namespace|all)\\b|\\bterraform\\s+destroy\\b'))
  ] AS hit,
  [
    -- destroy.delete
    substring(replace_regex(extract(multi_if(json_value(tool_input, '$[0].command') != '', json_value(tool_input, '$[0].command'), json_value(tool_input, '$.command') != '', json_value(tool_input, '$.command'), tool_input), '(rm\\s+-[^;&|]{1,140})'), '\\s+', ' '), 1, 160),
    -- destroy.action
    substring(replace_regex(extract(multi_if(json_value(tool_input, '$[0].command') != '', json_value(tool_input, '$[0].command'), json_value(tool_input, '$.command') != '', json_value(tool_input, '$.command'), tool_input), '((?:(?i)\\bgit\\s+push\\b[^;&|]*(--force|\\s-f)(\\s|$)[^;&|]*\\b(main|master|trunk|production|prod|release[\\w./\\-]*)\\b|\\bgit\\s+push\\b[^;&|]*\\b(main|master|trunk|production|prod|release[\\w./\\-]*)\\b[^;&|]*(--force|\\s-f)(\\s|$)|\\bgit\\s+reset\\s+--hard\\s+\\S*[~^][0-9]|\\bDROP\\s+(DATABASE|SCHEMA)\\b|\\bkubectl\\s+delete\\s+(ns|namespace|all)\\b|\\bterraform\\s+destroy\\b)[^;&|]{0,60})'), '\\s+', ' '), 1, 160)
  ] AS evidence
WHERE event_type IN ('tool_invoke')
  AND session_id != ''
  AND hit
