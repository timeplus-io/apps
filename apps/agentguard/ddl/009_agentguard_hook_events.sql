CREATE STREAM IF NOT EXISTS {{ .DB }}.agentguard_hook_events
(
  hook_name        low_cardinality(string),
  event_time       datetime64(3, 'UTC'),
  session_id       string,
  run_id           string,
  agent_id         string,
  deployment_id    low_cardinality(string),
  deployment_name  low_cardinality(string),
  session_key      string,
  tool_name        string,
  provider         string,
  model            string,
  hook_decision    low_cardinality(string),
  block_reason     string,
  event_data       string,
  agent_type       low_cardinality(string)
)
