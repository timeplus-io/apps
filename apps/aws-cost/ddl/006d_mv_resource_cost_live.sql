CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_resource_cost_live
INTO {{ .DB }}.aws_resource_cost_live
AS SELECT
  u.resource_id                         AS resource_id,
  u.service                             AS service,
  u.region                              AS region,
  u.resource_type                       AS resource_type,
  u.state                               AS state,
  u.creator                             AS creator,
  u.size_units                          AS size_units,
  u.unit                                AS unit,
  u.tags_json                           AS tags_json,
  u.snapshot_ts                         AS snapshot_ts,
  p.hourly_usd                          AS unit_hourly_usd,
  u.size_units * p.hourly_usd           AS hourly_cost_usd,
  u.size_units * p.hourly_usd * 730     AS monthly_cost_usd
FROM {{ .DB }}.aws_resource_usage_live AS u
LEFT JOIN {{ .DB }}.aws_prices AS p
  ON  u.service       = p.service
  AND u.region        = p.region
  AND u.resource_type = p.resource_type
  AND u.unit          = p.unit
WHERE u.snapshot_ts > now() - 90s;
