CREATE VIEW IF NOT EXISTS {{ .DB }}.v_post_volume
AS SELECT
  window_start        AS time,
  count(*)            AS post_count,
  count(distinct did) AS unique_posters
FROM tumble({{ .DB }}.bluesky_posts, 5s)
GROUP BY window_start;
