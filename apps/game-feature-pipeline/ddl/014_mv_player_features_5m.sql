CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_player_features_5m
INTO {{ .DB }}.player_features_5m
AS SELECT
    user_id,
    window_start AS ts,
    window_end AS te,
    count(*) AS events_5m,
    count() FILTER(WHERE event_type = 'match_start') AS matches_started_5m,
    count() FILTER(WHERE event_type = 'match_end') AS matches_completed_5m,
    avg(event_data:kills::float) AS avg_kills_5m,
    max(event_data:damage_dealt::float) AS max_damage_5m,
    count_distinct(match_id) AS unique_matches_5m
FROM tumble({{ .DB }}.player_actions, 5m)
WHERE _tp_time > earliest_ts()
GROUP BY user_id, window_start, window_end;
