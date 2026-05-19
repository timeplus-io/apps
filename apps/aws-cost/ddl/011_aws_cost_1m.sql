CREATE STREAM IF NOT EXISTS {{ .DB }}.aws_cost_1m (
  time              datetime64(3),
  total_hourly_usd  float64,
  resource_count    uint32
)
TTL to_datetime(time) + INTERVAL 30 DAY;
