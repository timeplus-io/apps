CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_github_events
INTO {{ .DB }}.github_events
AS
SELECT
  id, created_at, actor, type, repo, payload, to_time(created_at) AS _tp_time
FROM
  {{ .DB }}.github_events_stream
