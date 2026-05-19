CREATE VIEW IF NOT EXISTS {{ .DB }}.v_top_expensive AS
SELECT
  window_start                AS time,
  resource_id,
  service,
  region,
  resource_type,
  creator,
  any(hourly_cost_usd)        AS hourly_cost_usd,
  any(monthly_cost_usd)       AS monthly_cost_usd
FROM tumble({{ .DB }}.v_resource_cost_now, _tp_time, 1m)
WHERE state IN ('running','in-use','active')
  AND hourly_cost_usd IS NOT NULL
GROUP BY window_start, resource_id, service, region, resource_type, creator
ORDER BY hourly_cost_usd DESC
LIMIT 20;
