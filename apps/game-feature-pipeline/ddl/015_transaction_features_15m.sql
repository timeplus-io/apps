CREATE STREAM IF NOT EXISTS {{ .DB }}.transaction_features_15m
(
    user_id string,
    ts datetime64(3, 'UTC'),
    te datetime64(3, 'UTC'),
    transaction_count_15m uint64,
    total_spent_15m float64,
    avg_transaction_15m float64,
    max_transaction_15m float64,
    unique_categories_15m uint64,
    unique_devices_15m uint64,
    unique_cities_15m uint64
)
TTL to_datetime(_tp_time) + INTERVAL {{ .Config.stream_ttl_hours }} HOUR
SETTINGS logstore_retention_bytes = '{{ .Config.logstore_retention_bytes }}', logstore_retention_ms = '{{ .Config.logstore_retention_ms }}';
