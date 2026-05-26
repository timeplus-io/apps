CREATE STREAM IF NOT EXISTS {{ .DB }}.taxi_positions (
  car_id     string,
  ts         datetime64(3),
  longitude  float64,
  latitude   float64,
  speed_kmh  float64
)
TTL to_datetime(_tp_time) + INTERVAL 1 HOUR
SETTINGS logstore_retention_bytes = '107374182', logstore_retention_ms = '300000';
