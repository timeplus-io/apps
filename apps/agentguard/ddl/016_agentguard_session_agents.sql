CREATE MUTABLE STREAM IF NOT EXISTS {{ .DB }}.agentguard_session_agents
(
  session_id    string,
  agent_id      string,
  deployment_id string,
  first_seen    datetime64(3)
) PRIMARY KEY (session_id)
