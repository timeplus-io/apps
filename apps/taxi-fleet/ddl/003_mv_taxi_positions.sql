CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_taxi_positions
INTO {{ .DB }}.taxi_positions
AS
SELECT
  car_id,
  ts,
  longitude,
  latitude,
  speed_kmh,
  ts AS _tp_time
FROM {{ .DB }}.taxi_feed;
