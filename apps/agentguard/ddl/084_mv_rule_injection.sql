-- Detection rules: Prompt injection (timeplus-io/apps#86).
-- Instructions aimed at the agent, in the content it reads (files, web pages, MCP results) and in prompts.
-- Content is where an attacker's text arrives; a prompt is typed by the user, so the same phrases there are a lower severity.
-- One row is written per rule that matches, under the rule's own id and severity. A regex in a SQL
-- string needs every backslash doubled: a single \b is a backspace character, and the pattern never matches.
-- Command rules read the command of a shell tool call, not the text of a file being written or read.
CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_rule_injection
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
  ['inject.content', 'inject.prompt'] AS rule_id,
  ['Instructions to the agent in fetched content', 'Jailbreak phrasing in a prompt'] AS rule_name,
  ['high', 'low'] AS severity,
  [
    -- inject.content
    (event_type = 'tool_complete' AND ((tool_name IN ('Read', 'WebFetch', 'WebSearch', 'webrun', 'NotebookRead') OR tool_name LIKE 'mcp\\_\\_%') AND tool_result NOT LIKE '[{"type":"image"%' AND match(tool_result, '(?i)(ignore (all |any )?(the )?(previous|prior|above|earlier) (instructions|prompts)|disregard (all |your |the )?(previous |prior )?instructions|you are now (a|an|the) |new instructions:|do not (tell|mention|inform|reveal)[^.\\n]{0,40}\\b(user|human)\\b|forget (all |every)?(previous|prior) instructions)'))),
    -- inject.prompt
    (event_type = 'user_input' AND match(user_message, '(?i)(ignore (all |any )?(the )?(previous|prior|above|earlier) (instructions|prompts)|disregard (all |your |the )?(previous |prior )?instructions|\\bjailbr(eak|oken)\\b|\\b(dan|developer|god|unrestricted) mode\\b|you are (now )?(a |an )?free (ai|model|llm|assistant) without)'))
  ] AS hit,
  [
    -- inject.content
    substring(replace_regex(extract(tool_result, '((?i)(ignore (all |any )?(the )?(previous|prior|above|earlier) (instructions|prompts)|disregard (all |your |the )?(previous |prior )?instructions|you are now (a|an|the) |new instructions:|do not (tell|mention|inform|reveal)[^.\\n]{0,40}\\b(user|human)\\b|forget (all |every)?(previous|prior) instructions))'), '\\s+', ' '), 1, 160),
    -- inject.prompt
    substring(replace_regex(extract(user_message, '((?i)(ignore (all |any )?(the )?(previous|prior|above|earlier) (instructions|prompts)|disregard (all |your |the )?(previous |prior )?instructions|\\bjailbr(eak|oken)\\b|\\b(dan|developer|god|unrestricted) mode\\b|you are (now )?(a |an )?free (ai|model|llm|assistant) without))'), '\\s+', ' '), 1, 160)
  ] AS evidence
WHERE event_type IN ('tool_complete', 'user_input')
  AND session_id != ''
  AND hit
