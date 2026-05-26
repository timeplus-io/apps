CREATE VIEW IF NOT EXISTS {{ .DB }}.v_speed_per_car_1m AS
SELECT
  window_start AS time,
  car_id,
  round(avg(speed_kmh), 1) AS avg_speed_kmh,
  round(max(speed_kmh), 1) AS max_speed_kmh
FROM tumble({{ .DB }}.taxi_positions, 1m)
GROUP BY window_start, car_id;
