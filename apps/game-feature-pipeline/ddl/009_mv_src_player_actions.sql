CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_src_player_actions
INTO {{ .DB }}.player_actions
AS SELECT * FROM {{ .DB }}.src_player_actions;
