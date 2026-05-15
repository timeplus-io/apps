CREATE STREAM IF NOT EXISTS {{ .DB }}.execution
(
    event_ts        uint64,
    OrderId         string,
    TradeDate       date,
    SecurityAccount string,
    SecurityId      string,
    EntrustDirection string,
    LastQty         float64,
    LastPx          float64,
    Fee             float64,
    StrategyId      string
)
PARTITION BY to_start_of_hour(_tp_time)
TTL to_datetime(_tp_time) + INTERVAL {{ .Config.stream_ttl_hours }} HOUR
SETTINGS index_granularity = 8192, logstore_retention_bytes = '107374182', logstore_retention_ms = '300000';
