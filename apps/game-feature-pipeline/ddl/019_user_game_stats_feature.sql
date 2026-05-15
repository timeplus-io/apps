CREATE STREAM IF NOT EXISTS {{ .DB }}.user_game_stats_feature
(
    user_id string,
    total_game_played uint64,
    first_game_played string,
    last_game_played string
)
TTL to_datetime(_tp_time) + INTERVAL {{ .Config.stream_ttl_hours }} HOUR
SETTINGS logstore_retention_bytes = '{{ .Config.logstore_retention_bytes }}', logstore_retention_ms = '{{ .Config.logstore_retention_ms }}';
