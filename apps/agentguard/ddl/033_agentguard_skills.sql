CREATE STREAM IF NOT EXISTS {{ .DB }}.agentguard_skills
(
  event_time        datetime64(3),
  agent_id          string,
  session_id        string,
  deployment_id     string,
  agent_type        low_cardinality(string),
  skill_name        string,
  skill_action      low_cardinality(string),
  skill_namespace   low_cardinality(string),
  skill_source_type low_cardinality(string),
  skill_location    string,
  skill_description string,
  skill_args        string
)
