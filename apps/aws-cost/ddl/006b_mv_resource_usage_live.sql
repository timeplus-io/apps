CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_resource_usage_live
INTO {{ .DB }}.aws_resource_usage_live
AS SELECT
  resource_id,
  latest(service)        AS service,
  latest(region)         AS region,
  latest(resource_type)  AS resource_type,
  latest(state)          AS state,
  latest(creator)        AS creator,
  latest(size_units)     AS size_units,
  latest(unit)           AS unit,
  latest(tags_json)      AS tags_json,
  window_end             AS snapshot_ts
FROM hop({{ .DB }}.aws_resources, _tp_time, 1m, 5m)
GROUP BY window_end, resource_id;
