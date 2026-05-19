CREATE VIEW IF NOT EXISTS {{ .DB }}.v_resource_cost_now AS
SELECT
  r._tp_time                            AS _tp_time,
  r.service                             AS service,
  r.region                              AS region,
  r.resource_id                         AS resource_id,
  r.resource_type                       AS resource_type,
  r.state                               AS state,
  r.size_units                          AS size_units,
  r.unit                                AS unit,
  r.creator                             AS creator,
  r.tags_json                           AS tags_json,
  p.hourly_usd                          AS unit_hourly_usd,
  r.size_units * p.hourly_usd           AS hourly_cost_usd,
  r.size_units * p.hourly_usd * 730     AS monthly_cost_usd
FROM {{ .DB }}.aws_resources AS r
LEFT JOIN {{ .DB }}.aws_prices AS p
  ON  r.service       = p.service
  AND r.region        = p.region
  AND r.resource_type = p.resource_type
  AND r.unit          = p.unit;
