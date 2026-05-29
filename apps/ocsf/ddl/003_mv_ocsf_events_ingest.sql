CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_ocsf_events_ingest
INTO {{ .DB }}.ocsf_events AS
SELECT raw, class_uid
FROM {{ .DB }}.ocsf_events_source;
