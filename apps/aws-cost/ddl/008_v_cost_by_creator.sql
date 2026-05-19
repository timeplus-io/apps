CREATE VIEW IF NOT EXISTS {{ .DB }}.v_cost_by_creator AS
SELECT
  creator,
  sum(hourly_cost_usd)  AS hourly_usd,
  sum(monthly_cost_usd) AS monthly_usd,
  count()               AS resources
FROM {{ .DB }}.v_resource_cost_now
WHERE _tp_time > now() - 2m
  AND state IN ('running','in-use','active')
  AND hourly_cost_usd IS NOT NULL
GROUP BY creator
EMIT ON UPDATE WITH DELAY 5s;
