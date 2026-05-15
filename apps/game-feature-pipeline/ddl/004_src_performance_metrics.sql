CREATE RANDOM STREAM IF NOT EXISTS {{ .DB }}.src_performance_metrics
(
    user_id string DEFAULT concat('usr_', to_string(rand64(1) % 20000)),
    session_id string DEFAULT concat('sess_', to_string(rand64(2) % 1000)),
    timestamp datetime64(3) DEFAULT now64(3),
    device_stats string DEFAULT concat(
        '{',
          '"fps_avg":', to_string(round(rand_normal(60, 10), 1)), ',',
          '"fps_min":', to_string(round(rand_uniform(20, 60), 0)), ',',
          '"memory_usage_mb":', to_string(round(rand_normal(2048, 512), 0)), ',',
          '"battery_level":', to_string((rand(3) % 100)), ',',
          '"network_latency_ms":', to_string(round(rand_normal(50, 15), 0)), ',',
          '"packet_loss_pct":', to_string(round(rand_uniform(0.0, 2.0), 2)),
        '}'
    ),
    game_stats string DEFAULT concat(
        '{',
          '"load_time_ms":', to_string(round(rand_normal(3000, 500), 0)), ',',
          '"crash_occurred":', multi_if((rand(4) % 100) < 5, 'true', 'false'), ',',
          '"error_count":', to_string(rand(5) % 5),
        '}'
    )
)
SETTINGS eps = {{ .Config.performance_metrics_eps }};
