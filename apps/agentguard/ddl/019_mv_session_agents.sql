CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_session_agents
INTO {{ .DB }}.agentguard_session_agents AS
SELECT
  session_id,
  agent_id,
  deployment_id,
  event_time AS first_seen
FROM {{ .DB }}.agentguard_hook_events
