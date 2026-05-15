CREATE STREAM IF NOT EXISTS {{ .DB }}.user_technical_performance_feature
(
    user_id string,
    game_mode enum8('battle_royale' = 1, 'team_deathmatch' = 2, 'capture_the_flag' = 3),
    avg_fps_by_mode float64,
    avg_latency_by_mode float64
)
TTL to_datetime(_tp_time) + INTERVAL {{ .Config.stream_ttl_hours }} HOUR
SETTINGS logstore_retention_bytes = '{{ .Config.logstore_retention_bytes }}', logstore_retention_ms = '{{ .Config.logstore_retention_ms }}';
