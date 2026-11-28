-- Replaces mv_threats (#86). A detection becomes a threat unless its severity is `info` or `low`;
-- those detections stay in agentguard_security_events as a record. It reads from now on.
CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_threats_v2
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
WHERE severity NOT IN ('info', 'low')
