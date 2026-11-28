-- Detection rules: Exfiltration (timeplus-io/apps#86).
-- A credential file or the environment sent out of the machine in one shell command.
-- One row is written per rule that matches, under the rule's own id and severity. A regex in a SQL
-- string needs every backslash doubled: a single \b is a backspace character, and the pattern never matches.
-- Command rules read the command of a shell tool call, not the text of a file being written or read.
CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_rule_exfiltration
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
  ['exfil.send'] AS rule_id,
  ['Credentials sent to a remote host'] AS rule_name,
  ['critical'] AS severity,
  [
    -- exfil.send
    (lower(tool_name) IN ('bash', 'shell', 'exec', 'run_terminal_cmd', 'local_shell', 'terminal', 'computer') AND (match(multi_if(json_value(tool_input, '$[0].command') != '', json_value(tool_input, '$[0].command'), json_value(tool_input, '$.command') != '', json_value(tool_input, '$.command'), tool_input), '((\\.ssh/(id_[a-z0-9_]+|authorized_keys)|\\.aws/credentials|\\.netrc\\b|\\.npmrc\\b|\\.pypirc\\b|\\.docker/config\\.json|\\.kube/config|(^|[/\\s\\"\'=])\\.env(\\.[a-z]+)?(\\b|$)|/etc/(shadow|sudoers))|(^|[;&|(]\\s*)(env|printenv)\\b)[^;&]*\\|\\s*(curl|wget|nc|ncat)\\b') OR match(multi_if(json_value(tool_input, '$[0].command') != '', json_value(tool_input, '$[0].command'), json_value(tool_input, '$.command') != '', json_value(tool_input, '$.command'), tool_input), '\\b(curl|wget)\\b[^;&|]*(\\s-d|--data[a-z\\-]*|\\s-F|--form|\\s-T|--upload-file)\\s*[\\"\']?[^\\s\\"\']*(\\.ssh/(id_[a-z0-9_]+|authorized_keys)|\\.aws/credentials|\\.netrc\\b|\\.npmrc\\b|\\.pypirc\\b|\\.docker/config\\.json|\\.kube/config|(^|[/\\s\\"\'=])\\.env(\\.[a-z]+)?(\\b|$)|/etc/(shadow|sudoers))') OR match(multi_if(json_value(tool_input, '$[0].command') != '', json_value(tool_input, '$[0].command'), json_value(tool_input, '$.command') != '', json_value(tool_input, '$.command'), tool_input), '\\b(curl|wget)\\b[^;&|]*\\$\\([^)]*\\b(base64|cat|xxd)\\b[^)]*\\)')))
  ] AS hit,
  [
    -- exfil.send
    substring(replace_regex(extract(multi_if(json_value(tool_input, '$[0].command') != '', json_value(tool_input, '$[0].command'), json_value(tool_input, '$.command') != '', json_value(tool_input, '$.command'), tool_input), '([^;&]{0,60}\\b(curl|wget|nc|ncat)\\b[^;&]{0,100})'), '\\s+', ' '), 1, 160)
  ] AS evidence
WHERE event_type IN ('tool_invoke')
  AND session_id != ''
  AND hit
