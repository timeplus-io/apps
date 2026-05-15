CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_src_performance_metrics
INTO {{ .DB }}.performance_metrics
AS SELECT * FROM {{ .DB }}.src_performance_metrics;
