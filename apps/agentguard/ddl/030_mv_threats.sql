CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_threats
INTO {{ .DB }}.agentguard_threats
AS SELECT
    agent_id,
    deployment_id,
    session_id,
    rule_id,
    rule_name,
    severity,
    detected_at AS last_seen
FROM {{ .DB }}.agentguard_security_events
SETTINGS seek_to = 'earliest'
