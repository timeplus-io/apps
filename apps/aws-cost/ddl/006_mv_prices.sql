CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_prices
INTO {{ .DB }}.aws_prices
AS SELECT
  service,
  region,
  resource_type,
  unit,
  hourly_usd,
  effective_ts
FROM {{ .DB }}.aws_price_poller;
