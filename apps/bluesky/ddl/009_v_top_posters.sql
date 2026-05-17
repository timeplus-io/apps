CREATE VIEW IF NOT EXISTS {{ .DB }}.v_top_posters
AS SELECT
  window_start  AS time,
  did,
  count(*)      AS post_count,
  latest(text)  AS latest_post
FROM tumble({{ .DB }}.bluesky_posts, 5m)
GROUP BY window_start, did
HAVING post_count >= 2
ORDER BY post_count DESC;
