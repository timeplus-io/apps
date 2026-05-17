CREATE MUTABLE STREAM IF NOT EXISTS {{ .DB }}.bluesky_stats_1m (
  window_time  datetime64(3),
  collection   string,
  event_count  uint64,
  unique_users uint64,
  PRIMARY KEY (window_time, collection)
);
