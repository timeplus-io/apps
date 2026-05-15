CREATE VIEW IF NOT EXISTS {{ .DB }}.v_features_all AS
SELECT
    tsl10t._tp_time AS time,
    tsl10t.user_id AS user_id,
    tsl10t.total_spend AS total_spend,
    ugsf.total_game_played AS total_game_played,
    ugsf.first_game_played AS first_game_played,
    ugsf.last_game_played AS last_game_played,
    utpf.game_mode AS game_mode,
    utpf.avg_fps_by_mode AS avg_fps_by_mode,
    utpf.avg_latency_by_mode AS avg_latency_by_mode,
    pf5m.matches_started_5m AS matches_started_5m,
    pf5m.matches_completed_5m AS matches_completed_5m,
    pf5m.avg_kills_5m AS avg_kills_5m,
    pf5m.max_damage_5m AS max_damage_5m,
    pf5m.unique_matches_5m AS unique_matches_5m,
    tf15m.transaction_count_15m AS transaction_count_15m,
    tf15m.total_spent_15m AS total_spent_15m,
    tf15m.avg_transaction_15m AS avg_transaction_15m,
    tf15m.max_transaction_15m AS max_transaction_15m,
    tf15m.unique_categories_15m AS unique_categories_15m,
    tf15m.unique_devices_15m AS unique_devices_15m,
    tf15m.unique_cities_15m AS unique_cities_15m
FROM {{ .DB }}.total_spend_last_10_transaction AS tsl10t
ASOF LEFT JOIN {{ .DB }}.user_game_stats_feature ugsf
    ON tsl10t.user_id = ugsf.user_id
    AND (tsl10t._tp_time >= ugsf._tp_time)
ASOF LEFT JOIN {{ .DB }}.user_technical_performance_feature utpf
    ON tsl10t.user_id = utpf.user_id
    AND (tsl10t._tp_time >= utpf._tp_time)
ASOF LEFT JOIN {{ .DB }}.player_features_5m AS pf5m
    ON tsl10t.user_id = pf5m.user_id
    AND (tsl10t._tp_time >= pf5m.te)
ASOF LEFT JOIN {{ .DB }}.transaction_features_15m AS tf15m
    ON tsl10t.user_id = tf15m.user_id
    AND (tsl10t._tp_time >= tf15m.te);
