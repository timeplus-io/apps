CREATE STREAM IF NOT EXISTS {{ .DB }}.player_actions
(
    user_id string,
    session_id string,
    timestamp string,
    event_type enum8('match_start' = 1, 'item_pickup' = 2, 'player_elimination' = 3, 'match_end' = 4),
    game_mode enum8('battle_royale' = 1, 'team_deathmatch' = 2, 'capture_the_flag' = 3),
    match_id string,
    event_data string,
    device_info string
)
TTL to_datetime(_tp_time) + INTERVAL {{ .Config.stream_ttl_hours }} HOUR
SETTINGS logstore_retention_bytes = '{{ .Config.logstore_retention_bytes }}', logstore_retention_ms = '{{ .Config.logstore_retention_ms }}';
