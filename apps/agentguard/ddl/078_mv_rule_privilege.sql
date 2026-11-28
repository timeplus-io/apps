-- Detection rules: Privilege and persistence (timeplus-io/apps#86).
-- Privilege escalation and persistence, in shell commands.
-- One row is written per rule that matches, under the rule's own id and severity. A regex in a SQL
-- string needs every backslash doubled: a single \b is a backspace character, and the pattern never matches.
-- Command rules read the command of a shell tool call, not the text of a file being written or read.
CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_rule_privilege
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
  ['priv.sudo', 'priv.system-file', 'priv.chmod', 'priv.persist'] AS rule_id,
  ['Command run as another user', 'System account file touched', 'Unsafe file permissions set', 'Persistence or container escape'] AS rule_name,
  ['medium', 'high', 'medium', 'high'] AS severity,
  [
    -- priv.sudo
    (lower(tool_name) IN ('bash', 'shell', 'exec', 'run_terminal_cmd', 'local_shell', 'terminal', 'computer') AND match(multi_if(json_value(tool_input, '$[0].command') != '', json_value(tool_input, '$[0].command'), json_value(tool_input, '$.command') != '', json_value(tool_input, '$.command'), tool_input), '(^|[;&|(]\\s*)(sudo|doas)\\s+\\S')),
    -- priv.system-file
    (lower(tool_name) IN ('bash', 'shell', 'exec', 'run_terminal_cmd', 'local_shell', 'terminal', 'computer') AND match(multi_if(json_value(tool_input, '$[0].command') != '', json_value(tool_input, '$[0].command'), json_value(tool_input, '$.command') != '', json_value(tool_input, '$.command'), tool_input), '/etc/(shadow|sudoers)\\b|>\\s*/etc/passwd')),
    -- priv.chmod
    (lower(tool_name) IN ('bash', 'shell', 'exec', 'run_terminal_cmd', 'local_shell', 'terminal', 'computer') AND match(multi_if(json_value(tool_input, '$[0].command') != '', json_value(tool_input, '$[0].command'), json_value(tool_input, '$.command') != '', json_value(tool_input, '$.command'), tool_input), '(^|[;&|(]\\s*|\\b(then|do|else)\\s+)(sudo\\s+(-\\S+\\s+)*)?chmod\\s+(-[A-Za-z]+\\s+)*(0?777\\b|a\\+rwx|[ugoa]*\\+[rwx]*s|[2467][0-7]{3}\\b)')),
    -- priv.persist
    (lower(tool_name) IN ('bash', 'shell', 'exec', 'run_terminal_cmd', 'local_shell', 'terminal', 'computer') AND match(multi_if(json_value(tool_input, '$[0].command') != '', json_value(tool_input, '$[0].command'), json_value(tool_input, '$.command') != '', json_value(tool_input, '$.command'), tool_input), '\\|\\s*crontab\\s+-|(^|[;&|(]\\s*|\\b(then|do|else)\\s+)(sudo\\s+(-\\S+\\s+)*)?crontab\\s+-e\\b|--privileged\\b|\\b(LD_PRELOAD|DYLD_INSERT_LIBRARIES)=|(^|[;&|(]\\s*|\\b(then|do|else)\\s+)(sudo\\s+(-\\S+\\s+)*)?(nsenter|chroot)\\s'))
  ] AS hit,
  [
    -- priv.sudo
    substring(replace_regex(extract(multi_if(json_value(tool_input, '$[0].command') != '', json_value(tool_input, '$[0].command'), json_value(tool_input, '$.command') != '', json_value(tool_input, '$.command'), tool_input), '((sudo|doas)\\s+[^;&|]{1,140})'), '\\s+', ' '), 1, 160),
    -- priv.system-file
    substring(replace_regex(extract(multi_if(json_value(tool_input, '$[0].command') != '', json_value(tool_input, '$[0].command'), json_value(tool_input, '$.command') != '', json_value(tool_input, '$.command'), tool_input), '([^;&|]{0,80}(/etc/(shadow|sudoers)|>\\s*/etc/passwd)[^;&|]{0,40})'), '\\s+', ' '), 1, 160),
    -- priv.chmod
    substring(replace_regex(extract(multi_if(json_value(tool_input, '$[0].command') != '', json_value(tool_input, '$[0].command'), json_value(tool_input, '$.command') != '', json_value(tool_input, '$.command'), tool_input), '(chmod\\s+[^;&|]{1,140})'), '\\s+', ' '), 1, 160),
    -- priv.persist
    substring(replace_regex(extract(multi_if(json_value(tool_input, '$[0].command') != '', json_value(tool_input, '$[0].command'), json_value(tool_input, '$.command') != '', json_value(tool_input, '$.command'), tool_input), '((?:\\|\\s*crontab\\s+-|crontab\\s+-e\\b|\\b[a-z]+\\s+run\\s[^;&|]*--privileged|LD_PRELOAD=|DYLD_INSERT_LIBRARIES=|\\bnsenter\\s|\\bchroot\\s)[^;&|]{0,80})'), '\\s+', ' '), 1, 160)
  ] AS evidence
WHERE event_type IN ('tool_invoke')
  AND session_id != ''
  AND hit
