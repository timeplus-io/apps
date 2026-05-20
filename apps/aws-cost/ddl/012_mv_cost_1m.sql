CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_cost_1m
INTO {{ .DB }}.aws_cost_1m
AS SELECT
  window_end                          AS time,
  sum(size_units * hourly_usd)        AS total_hourly_usd,
  to_uint32(count())                  AS resource_count
FROM (
  SELECT
    window_end,
    resource_id,
    latest(service)        AS service,
    latest(region)         AS region,
    latest(resource_type)  AS resource_type,
    latest(unit)           AS unit,
    latest(state)          AS state,
    latest(size_units)     AS size_units
  FROM hop({{ .DB }}.aws_resources, _tp_time, 1m, 5m)
  GROUP BY window_end, resource_id
) AS u
LEFT JOIN {{ .DB }}.aws_prices AS p
  ON  u.service       = p.service
  AND u.region        = p.region
  AND u.resource_type = p.resource_type
  AND u.unit          = p.unit
WHERE u.state IN ('running','in-use','active')
GROUP BY window_end;
