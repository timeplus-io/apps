CREATE STREAM IF NOT EXISTS {{ .DB }}.total_spend_last_10_transaction
(
    user_id string,
    total_spend float64
)
TTL to_datetime(_tp_time) + INTERVAL {{ .Config.stream_ttl_hours }} HOUR
SETTINGS logstore_retention_bytes = '{{ .Config.logstore_retention_bytes }}', logstore_retention_ms = '{{ .Config.logstore_retention_ms }}';
