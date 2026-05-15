CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_user_technical_performance_feature
INTO {{ .DB }}.user_technical_performance_feature
AS SELECT
    pa.user_id,
    pa.game_mode,
    avg(pm.device_stats:fps_avg::float) AS avg_fps_by_mode,
    avg(pm.device_stats:network_latency_ms::float) AS avg_latency_by_mode
FROM {{ .DB }}.player_actions pa
JOIN {{ .DB }}.performance_metrics pm
    ON pa.user_id = pm.user_id
    AND pa.session_id = pm.session_id
    AND date_diff_within(2m)
GROUP BY pa.user_id, pa.game_mode
EMIT ON UPDATE WITH BATCH 2s
SETTINGS seek_to = 'earliest';
