CREATE STREAM IF NOT EXISTS {{ .DB }}.performance_metrics
(
    user_id string,
    session_id string,
    timestamp datetime64(3),
    device_stats string,
    game_stats string
)
TTL to_datetime(_tp_time) + INTERVAL {{ .Config.stream_ttl_hours }} HOUR
SETTINGS logstore_retention_bytes = '{{ .Config.logstore_retention_bytes }}', logstore_retention_ms = '{{ .Config.logstore_retention_ms }}';
