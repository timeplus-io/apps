CREATE VIEW IF NOT EXISTS {{ .DB }}.v_cost_by_creator AS
SELECT
  creator,
  sum(hourly_cost_usd)  AS hourly_usd,
  sum(monthly_cost_usd) AS monthly_usd,
  count()               AS resources
FROM {{ .DB }}.aws_resource_cost_live
WHERE state IN ('running','in-use','active')
  AND hourly_cost_usd IS NOT NULL
  AND snapshot_ts > now() - 90s
GROUP BY creator;
