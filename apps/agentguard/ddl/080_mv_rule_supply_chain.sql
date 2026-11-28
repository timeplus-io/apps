-- Detection rules: Supply chain (timeplus-io/apps#86).
-- Where code and packages come from, in shell commands. An ordinary install is recorded as information, not as a threat.
-- One row is written per rule that matches, under the rule's own id and severity. A regex in a SQL
-- string needs every backslash doubled: a single \b is a backspace character, and the pattern never matches.
-- Command rules read the command of a shell tool call, not the text of a file being written or read.
CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_rule_supply_chain
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
  ['supply.pipe-shell', 'supply.source', 'supply.install'] AS rule_id,
  ['Download piped into a shell', 'Package or code from an unusual source', 'Package installed'] AS rule_name,
  ['high', 'medium', 'info'] AS severity,
  [
    -- supply.pipe-shell
    match(multi_if(json_value(tool_input, '$[0].command') != '', json_value(tool_input, '$[0].command'), json_value(tool_input, '$.command') != '', json_value(tool_input, '$.command'), tool_input), '(^|[;&|(]\\s*|\\b(then|do|else)\\s+)(sudo\\s+(-\\S+\\s+)*)?(curl|wget)\\b[^;&]*\\|\\s*(sudo\\s+)?(ba|z|da)?sh\\b'),
    -- supply.source
    (lower(tool_name) IN ('bash', 'shell', 'exec', 'run_terminal_cmd', 'local_shell', 'terminal', 'computer') AND (match(multi_if(json_value(tool_input, '$[0].command') != '', json_value(tool_input, '$[0].command'), json_value(tool_input, '$.command') != '', json_value(tool_input, '$.command'), tool_input), '(^|[;&|(]\\s*|\\b(then|do|else)\\s+)(sudo\\s+(-\\S+\\s+)*)?(pip3?|uv pip)\\s+install\\b[^;&|]*--(extra-)?index-url') OR (match(multi_if(json_value(tool_input, '$[0].command') != '', json_value(tool_input, '$[0].command'), json_value(tool_input, '$.command') != '', json_value(tool_input, '$.command'), tool_input), '(^|[;&|(]\\s*|\\b(then|do|else)\\s+)(sudo\\s+(-\\S+\\s+)*)?git\\s+clone\\s+(https?|git|ssh)://') AND NOT match(multi_if(json_value(tool_input, '$[0].command') != '', json_value(tool_input, '$[0].command'), json_value(tool_input, '$.command') != '', json_value(tool_input, '$.command'), tool_input), '(?i)git\\s+clone\\s+\\S*(github\\.com|gitlab\\.com|bitbucket\\.org|codeberg\\.org)[/:]')) OR match(multi_if(json_value(tool_input, '$[0].command') != '', json_value(tool_input, '$[0].command'), json_value(tool_input, '$.command') != '', json_value(tool_input, '$.command'), tool_input), '(^|[;&|(]\\s*|\\b(then|do|else)\\s+)(sudo\\s+(-\\S+\\s+)*)?docker\\s+pull\\s+[a-z0-9\\-]+(\\.[a-z0-9\\-]+)+(:[0-9]+)?/'))),
    -- supply.install
    (lower(tool_name) IN ('bash', 'shell', 'exec', 'run_terminal_cmd', 'local_shell', 'terminal', 'computer') AND match(multi_if(json_value(tool_input, '$[0].command') != '', json_value(tool_input, '$[0].command'), json_value(tool_input, '$.command') != '', json_value(tool_input, '$.command'), tool_input), '(^|[;&|(]\\s*|\\b(then|do|else)\\s+)(sudo\\s+(-\\S+\\s+)*)?(npm|pnpm|yarn|pip3?|pipx|uv|poetry|cargo|gem|go|brew|apt-get|apt)\\s+(install|add)\\b'))
  ] AS hit,
  [
    -- supply.pipe-shell
    substring(replace_regex(extract(multi_if(json_value(tool_input, '$[0].command') != '', json_value(tool_input, '$[0].command'), json_value(tool_input, '$.command') != '', json_value(tool_input, '$.command'), tool_input), '((curl|wget)\\b[^;&]{0,140})'), '\\s+', ' '), 1, 160),
    -- supply.source
    substring(replace_regex(extract(multi_if(json_value(tool_input, '$[0].command') != '', json_value(tool_input, '$[0].command'), json_value(tool_input, '$.command') != '', json_value(tool_input, '$.command'), tool_input), '((pip3?\\s+install|uv\\s+pip\\s+install|git\\s+clone|docker\\s+pull)[^;&|]{0,140})'), '\\s+', ' '), 1, 160),
    -- supply.install
    substring(replace_regex(extract(multi_if(json_value(tool_input, '$[0].command') != '', json_value(tool_input, '$[0].command'), json_value(tool_input, '$.command') != '', json_value(tool_input, '$.command'), tool_input), '((npm|pnpm|yarn|pip3?|pipx|uv|poetry|cargo|gem|go|brew|apt-get|apt)\\s+(install|add)[^;&|]{0,120})'), '\\s+', ' '), 1, 160)
  ] AS evidence
WHERE event_type IN ('tool_invoke')
  AND session_id != ''
  AND hit
