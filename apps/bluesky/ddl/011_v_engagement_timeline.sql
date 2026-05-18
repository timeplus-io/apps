CREATE VIEW IF NOT EXISTS {{ .DB }}.v_engagement_timeline
AS SELECT
  window_start                                          AS time,
  count_if(collection = 'app.bsky.feed.post')           AS posts,
  count_if(collection = 'app.bsky.feed.like')           AS likes,
  count_if(collection = 'app.bsky.graph.follow')        AS follows,
  count_if(collection = 'app.bsky.feed.repost')         AS reposts,
  count(*)                                              AS total
FROM tumble({{ .DB }}.bluesky_activity, 1m)
GROUP BY window_start;
