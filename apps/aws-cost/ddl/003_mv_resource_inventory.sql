CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_resource_inventory
INTO {{ .DB }}.aws_resources
AS SELECT
  service,
  region,
  resource_id,
  resource_type,
  state,
  size_units,
  unit,
  tags_json,
  creator,
  snapshot_ts
FROM {{ .DB }}.aws_resource_poller;
