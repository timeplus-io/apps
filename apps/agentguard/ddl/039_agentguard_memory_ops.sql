CREATE STREAM IF NOT EXISTS {{ .DB }}.agentguard_memory_ops
(
  event_time      datetime64(3),
  session_id      string,
  agent_id        string,
  agent_type      low_cardinality(string),
  deployment_id   low_cardinality(string),
  memory_source   low_cardinality(string),
  memory_op       low_cardinality(string),
  tool_name       string,
  server_name     low_cardinality(string),
  memory_path     string,
  content_payload string
)
