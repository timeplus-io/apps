CREATE STREAM IF NOT EXISTS {{ .DB }}.github_events
(
  `id`         string,
  `created_at` string,
  `actor`      string,
  `type`       string,
  `repo`       string,
  `payload`    string
)
TTL to_datetime(_tp_time) + INTERVAL 7 DAY
SETTINGS logstore_retention_bytes = '107374182', logstore_retention_ms = '300000'
