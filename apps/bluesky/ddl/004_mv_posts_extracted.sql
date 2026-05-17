CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_posts_extracted
INTO {{ .DB }}.bluesky_posts
AS SELECT
  did,
  rkey,
  record_json:text                                        AS text,
  record_json:createdAt                                   AS created_at,
  json_value(record_json, '$.langs[0]')                   AS lang,
  json_value(record_json, '$."embed"."$type"')            AS embed_type,
  if(record_json:reply:parent:uri != '', 'reply', 'post') AS post_type,
  received_at                                             AS _tp_time
FROM {{ .DB }}.bluesky_jetstream
WHERE kind = 'commit' AND operation = 'create' AND collection = 'app.bsky.feed.post';
