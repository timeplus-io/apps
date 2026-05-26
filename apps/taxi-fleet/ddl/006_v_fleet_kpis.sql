CREATE VIEW IF NOT EXISTS {{ .DB }}.v_fleet_kpis AS
SELECT
  window_start AS time,
  count_distinct(car_id) AS active_cars,
  round(avg(speed_kmh), 1) AS avg_speed_kmh,
  round(max(speed_kmh), 1) AS max_speed_kmh,
  count() AS updates_in_window
FROM tumble({{ .DB }}.taxi_positions, 5s)
GROUP BY window_start;
