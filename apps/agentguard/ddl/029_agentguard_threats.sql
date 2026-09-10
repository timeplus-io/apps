CREATE MUTABLE STREAM IF NOT EXISTS {{ .DB }}.agentguard_threats
(
    agent_id          string,
    deployment_id     string,
    session_id        string,
    rule_id           string,
    rule_name         string,
    severity          string,
    last_seen         datetime64(3),
    status            string,
    status_updated_at datetime64(3),
    FAMILY cf_events(rule_name, severity, last_seen),
    FAMILY cf_status(status, status_updated_at)
) PRIMARY KEY (agent_id, deployment_id, session_id, rule_id)
SETTINGS coalesced = true
