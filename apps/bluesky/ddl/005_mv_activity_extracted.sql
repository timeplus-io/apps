CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_activity_extracted
INTO {{ .DB }}.bluesky_activity
AS SELECT
  did,
  kind,
  operation,
  collection,
  received_at AS _tp_time
FROM {{ .DB }}.bluesky_jetstream
WHERE kind = 'commit';
