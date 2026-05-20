CREATE VIEW IF NOT EXISTS {{ .DB }}.v_cost_by_service_region AS
SELECT
  service,
  region,
  sum(hourly_cost_usd) AS hourly_usd,
  count()              AS resources
FROM {{ .DB }}.aws_resource_cost_live
WHERE state IN ('running','in-use','active')
  AND hourly_cost_usd IS NOT NULL
  AND snapshot_ts > now() - 90s
GROUP BY service, region;
