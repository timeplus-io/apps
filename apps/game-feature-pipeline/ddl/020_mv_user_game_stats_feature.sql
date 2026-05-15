CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_user_game_stats_feature
INTO {{ .DB }}.user_game_stats_feature
AS SELECT
    user_id,
    count_distinct(match_id) AS total_game_played,
    earliest(match_id) AS first_game_played,
    latest(match_id) AS last_game_played
FROM {{ .DB }}.player_actions
WHERE event_type = 'match_start' AND _tp_time > earliest_ts()
GROUP BY user_id
EMIT ON UPDATE WITH BATCH 2s
SETTINGS seek_to = 'earliest';
