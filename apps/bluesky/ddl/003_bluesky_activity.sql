CREATE STREAM IF NOT EXISTS {{ .DB }}.bluesky_activity (
  did        string,
  kind       string,
  operation  string,
  collection string,
  _tp_time   datetime64(3) DEFAULT now64(3)
)
TTL to_datetime(_tp_time) + INTERVAL 24 HOUR;
