CREATE STREAM IF NOT EXISTS {{ .DB }}.market_data
(
  `time`     datetime64(3, 'UTC'),
  `stock_id` string,
  `price`    float64,
  `volume`   uint32
)
PARTITION BY to_start_of_hour(_tp_time)
TTL to_datetime(_tp_time) + INTERVAL 1 HOUR
SETTINGS logstore_retention_ms = '3600000'
