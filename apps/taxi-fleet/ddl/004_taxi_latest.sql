CREATE MUTABLE STREAM IF NOT EXISTS {{ .DB }}.taxi_latest (
  car_id     string,
  ts         datetime64(3),
  longitude  float64,
  latitude   float64,
  speed_kmh  float64
)
PRIMARY KEY car_id;
