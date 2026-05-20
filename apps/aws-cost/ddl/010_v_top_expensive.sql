CREATE VIEW IF NOT EXISTS {{ .DB }}.v_top_expensive AS
SELECT
  now() AS time,
  r.1 AS hourly_cost_usd,
  r.2 AS resource_id,
  r.3 AS service,
  r.4 AS region,
  r.5 AS resource_type,
  r.6 AS creator,
  r.7 AS monthly_cost_usd
FROM (
  SELECT
    array_join(max_k(
      hourly_cost_usd, 20,
      resource_id, service, region, resource_type, creator, monthly_cost_usd
    )) AS r
  FROM {{ .DB }}.aws_resource_cost_live
  WHERE state IN ('running','in-use','active')
    AND hourly_cost_usd IS NOT NULL
    AND snapshot_ts > now() - 90s
);
