CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_hn_story_embedding
INTO {{ .DB }}.hn_story AS
SELECT
  to_uint64_or_zero(message:id) AS id,
  message:title AS title,
  message:text AS text,
  message:url AS url,
  message:by AS by,
  to_uint32_or_zero(message:score) AS score,
  to_datetime(to_int64_or_zero(message:time)) AS time,
  embed_text(concat(message:title, ' ', message:text)) AS embedding
FROM {{ .DB }}.hn_post
WHERE message:type = 'story' AND message:title != '' AND message:deleted != 'true' AND message:dead != 'true';
