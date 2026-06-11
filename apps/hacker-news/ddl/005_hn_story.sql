CREATE STREAM IF NOT EXISTS {{ .DB }}.hn_story (
  id uint64,
  title string,
  text string,
  url string,
  by string,
  score uint32,
  time datetime,
  embedding array(float32)
)
TTL to_datetime(_tp_time) + INTERVAL {{ .Config.stream_ttl_days }} DAY
SETTINGS logstore_retention_bytes = '{{ .Config.logstore_retention_bytes }}', logstore_retention_ms = '{{ .Config.logstore_retention_ms }}';
