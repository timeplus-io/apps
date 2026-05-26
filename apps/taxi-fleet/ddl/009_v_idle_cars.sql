CREATE VIEW IF NOT EXISTS {{ .DB }}.v_idle_cars AS
SELECT
  window_start AS time,
  car_id,
  round(max(speed_kmh), 1) AS max_speed_kmh,
  round(avg(speed_kmh), 1) AS avg_speed_kmh,
  any(longitude) AS longitude,
  any(latitude) AS latitude
FROM tumble({{ .DB }}.taxi_positions, 10s)
GROUP BY window_start, car_id
HAVING max(speed_kmh) < 5;
