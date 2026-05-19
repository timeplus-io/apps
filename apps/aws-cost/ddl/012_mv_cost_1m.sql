CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_cost_1m
INTO {{ .DB }}.aws_cost_1m
AS SELECT
  window_start                  AS time,
  sum(hourly_cost_usd)          AS total_hourly_usd,
  to_uint32(count())            AS resource_count
FROM tumble({{ .DB }}.v_resource_cost_now, _tp_time, 1m)
WHERE state IN ('running','in-use','active')
  AND hourly_cost_usd IS NOT NULL
GROUP BY window_start;
