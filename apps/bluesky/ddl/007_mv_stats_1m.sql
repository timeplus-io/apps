CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_stats_1m
INTO {{ .DB }}.bluesky_stats_1m
AS SELECT
  window_start        AS window_time,
  collection,
  count(*)            AS event_count,
  count(distinct did) AS unique_users
FROM tumble({{ .DB }}.bluesky_activity, 1m)
GROUP BY window_start, collection;
