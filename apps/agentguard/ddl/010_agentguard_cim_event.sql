CREATE STREAM IF NOT EXISTS {{ .DB }}.agentguard_cim_event
(
  event_time        datetime64(3),
  event_type        low_cardinality(string),
  agent_type        low_cardinality(string),
  agent_id          string,
  deployment_id     low_cardinality(string),
  session_id        string,
  run_id            string,
  provider          low_cardinality(string),
  model             low_cardinality(string),
  tool_name         string,
  tool_input        string,
  tool_result       string,
  tool_success      bool,
  tool_duration_ms  int64,
  user_message      string,
  assistant_message string,
  hook_decision     low_cardinality(string),
  block_reason      string,
  raw_hook_name     low_cardinality(string),
  raw_event_data    string
)
