CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_cfg
INTO {{ .DB }}.cfg
AS SELECT * FROM {{ .DB }}.generate_cfg_data;
