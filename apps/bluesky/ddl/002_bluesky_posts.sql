CREATE STREAM IF NOT EXISTS {{ .DB }}.bluesky_posts (
  did        string,
  rkey       string,
  text       string,
  created_at string,
  lang       string,
  embed_type string,
  post_type  string,
  _tp_time   datetime64(3) DEFAULT now64(3)
)
TTL to_datetime(_tp_time) + INTERVAL 24 HOUR;
