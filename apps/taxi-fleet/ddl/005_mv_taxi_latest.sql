CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_taxi_latest
INTO {{ .DB }}.taxi_latest
AS
SELECT car_id, ts, longitude, latitude, speed_kmh
FROM {{ .DB }}.taxi_positions;
