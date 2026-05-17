CREATE VIEW IF NOT EXISTS {{ .DB }}.v_language_breakdown
AS SELECT
  window_start                                      AS time,
  if(lang = '' OR lang IS NULL, 'unknown', lang)   AS language,
  count(*)                                          AS post_count
FROM tumble({{ .DB }}.bluesky_posts, 1m)
GROUP BY window_start, language
ORDER BY post_count DESC;
