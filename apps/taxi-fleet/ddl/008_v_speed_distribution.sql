CREATE VIEW IF NOT EXISTS {{ .DB }}.v_speed_distribution AS
SELECT
  window_start AS time,
  multi_if(
    speed_kmh < 10, '0-10',
    speed_kmh < 20, '10-20',
    speed_kmh < 40, '20-40',
    speed_kmh < 60, '40-60',
    speed_kmh < 80, '60-80',
    '80+'
  ) AS bucket,
  count() AS cars_in_bucket
FROM tumble({{ .DB }}.taxi_positions, 5s)
GROUP BY window_start, bucket;
