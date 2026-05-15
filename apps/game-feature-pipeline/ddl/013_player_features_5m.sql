CREATE STREAM IF NOT EXISTS {{ .DB }}.player_features_5m
(
    user_id string,
    ts datetime64(3, 'UTC'),
    te datetime64(3, 'UTC'),
    events_5m uint64,
    matches_started_5m uint64,
    matches_completed_5m uint64,
    avg_kills_5m float64,
    max_damage_5m float32,
    unique_matches_5m uint64
)
TTL to_datetime(_tp_time) + INTERVAL {{ .Config.stream_ttl_hours }} HOUR
SETTINGS logstore_retention_bytes = '{{ .Config.logstore_retention_bytes }}', logstore_retention_ms = '{{ .Config.logstore_retention_ms }}';
