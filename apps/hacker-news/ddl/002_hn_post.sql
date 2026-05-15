CREATE STREAM IF NOT EXISTS {{ .DB }}.hn_post (message string)
TTL to_datetime(_tp_time) + INTERVAL {{ .Config.stream_ttl_days }} DAY
SETTINGS logstore_retention_bytes = '{{ .Config.logstore_retention_bytes }}', logstore_retention_ms = '{{ .Config.logstore_retention_ms }}';
